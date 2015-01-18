#!/usr/bin/perl -w

use strict;
use Irssi;
use vars qw($VERSION %IRSSI);

$VERSION = "1.02";

%IRSSI = (
  authors     => 'Julie LaLa',
  contact     => 'ryz@asdf.us',
  name        => 'xdcc.pl',
  description => 'This script sets up a little XDCC server.',
  license     => 'Jollo LNT license',
  url         => 'http://asdf.us/xdcc/',
  changed     => 'Wed Jan 15 23:55:44 EST 2015',
);

my @files;
my @queue;

my $queue_max = 99;
my $bother_delay = 9999;

my $irssidir = Irssi::get_irssi_dir();
my $dcc_upload_path = Irssi::settings_get_str('dcc_upload_path');
my $sending = 0;
my $disabled = 0;
my $timeout = undef;
my $dcc = undef;
my $stats = {
  files_sent => 0,
  files => {},
  users => {},
};

my $help_local = <<EOF;

Usage:
/XDCC [-add <filename> <description>] [-del <id>] [-list] [-stats] [-help]

-add:     Add a file to our XDCC server
-del:     Remove a file from the offerings
-list:    Display the XDCC list (default)
-reset:   Reset the file list and the queue
-stats:   Statistics for this session
-enable:  Enable the XDCC server
-disable: Disable the XDCC server
-help:    Display this help.

Examples:
/xdcc -add sally.gif Jollo in his native habitat :)
/xdcc -add jollo.mp3 Distant cry of the Jollo, 5:43 am
/xdcc -del 1

Note: The default parameter is -list.

People can request files from you using these commands:
/ctcp <nickname> XDCC list
/ctcp <nickname> XDCC get 1
/ctcp <nickname> XDCC batch 2-4
/ctcp <nickname> XDCC queue

Only one file will be sent at a time.
Additional requests are added to a queue.
Filenames should not contain spaces.

EOF

my $help_remote = <<EOF;
[%_XDCC%_] plugin $VERSION
/ctcp %nick XDCC [get %_X%_] [batch %_X-Y%_] [remove %_X%_] [list] [queue] [version] [help] [about]
EOF

my $help_about = <<EOF;
[%_XDCC%_] irssi plugin $VERSION by $IRSSI{authors}
[%_XDCC%_] more info: $IRSSI{url}
EOF

Irssi::theme_register([
  'xdcc_sending_file',   '[%_XDCC%_] Sending the file [$0] %_$2%_ to %_$1%_',
  'xdcc_no_files',       '[%_XDCC%_] No files offered',
  'xdcc_print_file',     '[%_XDCC%_] [%_$0%_] %_$1%_ ... %_$2%_',
  'xdcc_queue_empty',    '[%_XDCC%_] The queue is currently empty',
  'xdcc_hr',             '[%_XDCC%_] ----',
  'xdcc_print_queue',    '[%_XDCC%_] $0. $1 - [$2] $3',
  'xdcc_file_not_found', '[%_XDCC%_] File does not exist',
  'xdcc_added_file',     '[%_XDCC%_] Added [$0] $1',
  'xdcc_removed_file',   '[%_XDCC%_] Removed [$0] $1',
  'xdcc_reset',          '[%_XDCC%_] Reset!',
  'xdcc_log',            '[%_XDCC%_] $0',
  'xdcc_stats',          '[%_XDCC%_] $0 ... %_$1%_',

  'xdcc_help', '$0',
  'xdcc_version', $help_about,
  'loaded', '%R>>%n %_Scriptinfo:%_ Loaded $0 version $1 by $2.'
]);

my $messages = {
  'queue_is_full'      => "[%_XDCC%_] The XDCC queue is currently full.",
  'queue_is_empty'     => "[%_XDCC%_] The XDCC queue is currently empty.",
  'no_files_offered'   => "[%_XDCC%_] Sorry, there's no warez today",
  'illegal_index'      => "[%_XDCC%_] Bad index for batch request",

  'file_entry'         => '[%_XDCC%_] [%d] %s ... %s',
  'file_count'         => '[%_XDCC%_] %d file%s',
  'file_help_get'      => '[%_XDCC%_] Type %_/ctcp %nick xdcc get N%_ to request a file',

  'in_queue'           => '[%_XDCC%_] You are #%d in queue. Requested [%d] %s',
  'queue_length'       => '[%_XDCC%_] %d request%s in queue',
  'sending_file'       => '[%_XDCC%_] Sending you %s ...!',
  'file_help_send'     => '[%_XDCC%_] Type %_/dcc %nick get%_ to accept the file',

  'xdcc_final_warning' => '[%_XDCC%_] This is your last warning!',
  'xdcc_inactive'      => '[%_XDCC%_] The DCC transfer has been cancelled for inactivity.',
  'xdcc_removed'       => '[%_XDCC%_] Your request has been removed.',
  'xdcc_file_removed'  => '[%_XDCC%_] The file you requested [%d] has been removed.',
  'xdcc_autoget_tip'   => '[%_XDCC%_] Tip: in irssi, type %_/set dcc_autoget ON%_',

  'xdcc_help'          => $help_remote,
  'xdcc_about'         => $help_about,
  'xdcc_version'       => "[%_XDCC%_] plugin $VERSION",
};

# Public XDCC request API
sub ctcp_reply {
  my ($server, $data, $nick, $address, $target) = @_;

  my ($ctcp, $cmd, $index) = split (" ", lc($data), 3);

  if ($disabled || $ctcp ne "xdcc") { return; }
     if ($cmd eq "get")     { xdcc_enqueue($server, $nick, $index) }
  elsif ($cmd eq "send")    { xdcc_enqueue($server, $nick, $index) }
  elsif ($cmd eq "batch")   { xdcc_batch($server, $nick, $index) }
  elsif ($cmd eq "info")    { xdcc_info($server, $nick, $index) }
  elsif ($cmd eq "remove")  { xdcc_remove($server, $nick, $index) }
  elsif ($cmd eq "queue")   { xdcc_queue($server, $nick) }
  elsif ($cmd eq "list")    { xdcc_list($server, $nick) }
  elsif ($cmd eq "version") { xdcc_message($server, $nick, 'xdcc_version') }
  elsif ($cmd eq "help")    { xdcc_message($server, $nick, 'xdcc_help') }
  elsif ($cmd eq "about")   { xdcc_message($server, $nick, 'xdcc_about') }
  else                      { xdcc_list($server, $nick) }

  Irssi::signal_stop();
}
sub xdcc_message {
  my ($server, $nick, $msgname, @params) = @_;
  my (@msgs) = split ("\n", $messages->{$msgname});
  for my $msg (@msgs) {
    $msg =~ s/%_/\x02/g;
    $msg =~ s/%-/\x03/g;
    $msg =~ s/%nick/$server->{nick}/g;
    $msg = sprintf $msg, @params;
    $server->send_message( $nick, $msg, 1 );
  }
}
sub xdcc_enqueue {
  my ($server, $nick, $index) = @_;
  my $id = int $index;
  $id -= 1;

  my $request = {
    server => $server,
    nick => $nick,
    id => $id
  };

  if (scalar @files == 0) {
    xdcc_message( $server, $nick, 'no_files_offered' );
    return;
  }
  if (! $sending && @queue == 0) {
    xdcc_send($request);
    return;
  }
  elsif (@queue > $queue_max) {
    xdcc_message( $server, $nick, 'queue_is_full' );
    return;
  }
  push(@queue, $request);
  xdcc_queue($server, $nick);
}
sub xdcc_batch {
  my ($server, $nick, $index) = @_;
  if ($index !~ /-/) {
    xdcc_message( $server, $nick, 'illegal_index' );
    return;
  }
  my ($from, $to) = split("-", $index, 2);
  $from = int $from;
  $to = int $to;
  if ($from > $to || $from < 1 || $to < 1 || $from > @files || $to > @files) {
    xdcc_message( $server, $nick, 'illegal_index' );
    return;
  }
  for (var $i = $from; $i <= $to; $i++) {
    xdcc_enqueue($server, $nick, $i);
  }
}
sub xdcc_remove {
  my ($server, $nick, $index) = @_;
  my $id = int $index;
  $id -= 1;

  my $removed;
  for (my $n = @queue; $n >= 0; --$n) {
    if ($queue[$n]->{nick} eq $nick && ($id == -1 || queue[$n]->{id} == $id)) {
      $removed = splice(@queue, $n, 1);
    }
  }
  if ($removed) {
    xdcc_message( $server, $nick, 'xdcc_removed' );
  }
}
sub xdcc_info {
  my ($server, $nick, $index) = @_;
  my $id = int $index;
  if (! $id) return;
  $id -= 1;
  # get stat data
}
sub xdcc_list {
  my ($server, $nick) = @_;
  if (scalar @files == 0) {
    xdcc_message( $server, $nick, 'no_files_offered' );
    return;
  }
  my ($msg, $file);
  for (my $n = 0; $n < @files ; ++$n) {
    xdcc_message( $server, $nick, 'file_entry', $n+1, $files[$n]->{fn}, $files[$n]->{desc} );
  }
  xdcc_message( $server, $nick, 'file_count', scalar @files, scalar @files == 1 ? "" : "s" );
  xdcc_message( $server, $nick, 'file_help_get');
}
sub xdcc_queue {
  my ($server, $nick) = @_;
  if (scalar @queue == 0) {
    xdcc_message( $server, $nick, 'queue_is_empty' );
    return
  }
  my $msg;
  for (my $n = 0; $n < @queue; ++$n) {
    if ($queue[$n]->{nick} eq $nick) {
      xdcc_message( $server, $nick, 'in_queue', $n+1, $queue[$n]->{id}+1, $files[$queue[$n]->{id}]->{fn} )
      # break
    }
  }
  xdcc_message( $server, $nick, 'queue_length', scalar @queue, scalar @queue == 1 ? "" : "s" )
}
sub xdcc_send {
  my ($request) = @_;
  my $server = $request->{server};
  my $nick = $request->{nick};
  my $id = $request->{id};
  my $file = $files[$id];
  my $path = $file->{path};
  xdcc_message( $server, $nick, 'sending_file', $file->{fn} );
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_sending_file', $id, $nick, $file->{fn});
  $server->command("/DCC send $nick $path");
  $sending = 1;
  $stats->{files_sent}++;
  $stats->{users}->{$nick} ||= 0;
  $stats->{users}->{$nick}++;
  $stats->{files}->{$file->{fn}} ||= 0;
  $stats->{files}->{$file->{fn}}++;
}

# XDCC command control
sub xdcc_report {
  if (scalar @files == 0) {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_no_files');
  }
  else {
    for (my $n = 0; $n < @files ; ++$n) {
      Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_print_file', $n+1, $files[$n]->{fn}, $files[$n]->{desc});
    }
  }
  if (scalar @queue == 0) {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_queue_empty');
  }
  else {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_hr');
    for (my $n = 0; $n < @files ; ++$n) {
      Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_print_queue', $n+1, $queue[$n]->{nick}, $queue[$n]->{id}, $files[$queue[$n]->{id}-1]->{fn});
    }
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_hr');
  }
}
sub xdcc_stats {
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_stats', "plugin version", $VERSION);
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_stats', "files sent", $stats->{files_sent});
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_hr');

  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'top files');
  map  { Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_stats', $_->[0], $_->[1]) }
  sort { $b->[1] <=> $a->[1] }
  map  { [$_, $stats->{files}->{$_}] }
  keys %{ $stats->{files} };
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_hr');

  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'top users');
  map  { Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_stats', $_->[0], $_->[1]) }
  sort { $b->[1] <=> $a->[1] }
  map  { [$_, $stats->{users}->{$_}] }
  keys %{ $stats->{users} };
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_hr');
}
sub xdcc_add {
  my ($path, $desc) = @_;
  if ($path !~ /^[\/~]/) {
    $path = $dcc_upload_path . "/" . $path;
  }
  if ($path =~ /^[~]/) {
    $path =~ s/^~//;
    $path = $ENV{"HOME"} . $path;
  }
  if (! -e $path) {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_file_not_found');
    return;
  }

  my $fn = $path;
  $fn =~ s|^.*\/||;

  my $id = scalar @files;

  my $file = {
    id => $id,
    fn => $fn,
    path => $path,
    desc => $desc,
  };

  push(@files, $file);

  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_added_file', $id+1, $fn);
}
sub xdcc_del {
  my ($id) = @_;
  $id = (int $id) - 1;
  my $file = $files[$id];
  my $req;

  splice(@files, $id, 1);

  for (my $n = @queue; $n >= 0; --$n) {
    if ($queue[$n]->{id} == $id) {
      $req = splice(@queue, $n, 1);
      xdcc_message( $req->{server}, $req->{nick}, 'xdcc_file_removed', $n );
    }
    elsif ($queue[$n]->{id} > $id) {
      --$queue[$n]->{id};
    }
  }

  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_removed_file', $id+1, $file->{fn});
}
sub xdcc_reset {
  @files = ();
  @queue = ();
  if ($dcc) { $dcc->destroy() }
  $sending = 0;
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_reset');
}
sub xdcc_help {
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_help', $help_local);
}

sub xdcc {
  my ($cmd, $fn, $desc) = split (" ", $_[0], 3);

  $cmd = lc($cmd);
  $cmd =~ s/^-//;

     if ($cmd eq "add")     { xdcc_add($fn, $desc) }
  elsif ($cmd eq "del")     { xdcc_remove($fn) }
  elsif ($cmd eq "list")    { xdcc_report() }
  elsif ($cmd eq "reset")   { xdcc_reset() }
  elsif ($cmd eq "stats")   { xdcc_stats() }
  elsif ($cmd eq "enable")  { $disabled = 0 }
  elsif ($cmd eq "disable") { $disabled = 1 }
  elsif ($cmd eq "help")    { xdcc_help() }
  elsif ($cmd eq "version") { xdcc_version() }
   else                     { xdcc_report() }
}

# DCC management
sub dcc_created {
  my ($dcc) = @_;
  # Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc created');
  if ($timeout) { Irssi::timeout_remove($timeout) }
  $timeout = Irssi::timeout_add_once($bother_delay, \&xdcc_bother, { dcc => $dcc, times => 1 });
}
sub xdcc_bother {
  my ($data) = @_;
  my $dcc = $data->{dcc};
  my $times = $data->{times};
  if ($times == 3) {
    xdcc_message($dcc->{server}, $dcc->{nick}, 'xdcc_final_warning');
  }
  if ($times <= 3) {
    xdcc_message($dcc->{server}, $dcc->{nick}, 'file_help_send');
    $data->{times}++;
    $timeout = Irssi::timeout_add_once($bother_delay, \&xdcc_bother, $data);
  }
  else {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'Send to ' . $dcc->{nick} . ' timed out.');
    xdcc_message($dcc->{server}, $dcc->{nick}, 'xdcc_inactive');
    xdcc_message($dcc->{server}, $dcc->{nick}, 'xdcc_autoget_tip');
    $dcc->destroy();
    undef $timeout;
    return
  }
}
sub dcc_destroyed {
  # Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc destroyed');
  if ($timeout) { Irssi::timeout_remove($timeout) }
  $sending = 0;
  if (@queue == 0) { return; }
  my $request = shift @queue;
  xdcc_send($request);
}
sub dcc_connected {
#  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc connected');
  if ($timeout) { Irssi::timeout_remove($timeout) }
}
sub dcc_rejecting {
#  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc rejecting');
}
sub dcc_closed {
#  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc closed');
}

# listen for xdcc end/cancel/close
Irssi::signal_add('dcc created',      'dcc_created');
Irssi::signal_add('dcc destroyed',    'dcc_destroyed');
Irssi::signal_add('dcc connected',    'dcc_connected');
Irssi::signal_add('dcc rejecting',    'dcc_rejecting');
Irssi::signal_add('dcc closed',       'dcc_closed');
Irssi::signal_add('default ctcp msg', 'ctcp_reply');
Irssi::command_bind('xdcc', 'xdcc');
Irssi::command_set_options('xdcc','add del list stats enable disable reset help version');
Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'loaded', $IRSSI{name}, $VERSION, $IRSSI{authors});
