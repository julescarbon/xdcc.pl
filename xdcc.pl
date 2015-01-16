#!/usr/bin/perl -w

use strict;
use Irssi;
use Switch;
use vars qw($VERSION %IRSSI);

$VERSION = "1.00";

%IRSSI = (
	authors     => 'Julie LaLa',
	contact     => 'jules@okfoc.us',
	name        => 'xdcc.pl',
	description => 'This script sets up a little XDCC server.',
	license     => 'GNU General Public License',
	url         => 'http://asdf.us/xdcc/xdcc.pl',
	changed     => 'Wed Jan 15 23:55:44 EST 2015',
);

my @files, @queue;

my $irssidir = Irssi::get_irssi_dir();

my $help = <<EOF;

Usage:
/XDCC [-add <filename> <description>] [-del <id>] [-list] [-help]

-add:     Add a file to our XDCC server.
-del:     Remove a file from the offerings.
-list:    Display the XDCC list.
-help:    Display this help.

Examples:
/xdcc -add jollo.png Jollo in his native habitat :)
/xdcc -add jollo.mp3 Distant cry of the Jollo, 5:43 am
/xdcc -del 1

Note: The default parameter is -list.

People can request files from you using these commands: 
/ctcp <nickname> XDCC list
/ctcp <nickname> XDCC send 1
/ctcp <nickname> XDCC queue

Only one file will be sent at a time.
Additional requests are added to a queue.
Filenames should not contain spaces.

EOF

Irssi::theme_register([
	'xdcc_request', '%R>>%n %_XDCC:%_ Sending the file %_$1%_ to %_$0%_',
	'xdcc_print', '$[!-2]0 $[20]1 $2',

	'xdcc_sending_file', '[%_XDCC:%_] Sending the file %_$1%_ to %_$0%_',
	'xdcc_no_files',     '[%_XDCC:%_] No files offered',
	'xdcc_print_file',   '[%_XDCC:%_] [%_$0%_] %_$1%_ ... %_$2%_',
	'xdcc_queue_empty',  '[%_XDCC:%_] The queue is currently empty',
	'xdcc_hr',           '[%_XDCC:%_] ----',
	'xdcc_print_queue',  '[%_XDCC:%_] $0. $1 - [$2] $3',
	'xdcc_file_dne',     '[%_XDCC:%_] File does not exist',
	'xdcc_added_file',   '[%_XDCC:%_] Added [$0] $1',
	'xdcc_removed_file', '[%_XDCC:%_] Removed [$0] $1',
	'xdcc_reset',        '[%_XDCC:%_] Reset!',

	'xdcc_help', '$0',
	'loaded', '%R>>%n %_Scriptinfo:%_ Loaded $0 version $1 by $2.'
]);

my $m = {
	'queue_is_full' => "The XDCC queue is currently full.",
	'no_files_offered' => "Sorry there's no warez today",
	'queue_is_empty' => "The XDCC queue is currently empty.",
};

sub ctcp_reply {
	my ($server, $data, $nick, $address, $target) = @_;

	my ($cmd, $index) = split (" ", lc($data), 3);

	switch ($cmd) {
		case "get"   { xdcc_enqueue($server, $index, $nick) }
		case "send"  { xdcc_enqueue($server, $index, $nick) }
		case "list"  { xdcc_list($server, $index, $nick) }
		case "queue" { xdcc_queue($server, $nick) }
	}

	Irssi::signal_stop();
}
sub xdcc_enqueue {
	my ($server, $index, $nick) = @_;
	$index = int $index;
	$index -= 1;
	if (@queue == 0) {
		return xdcc_send($server, $index, $nick);
	}
	else if (@queue > $queue_max) {
		$server->send_message( $nick, $m->{'queue_is_full'}, 1 );
		return;
	}
	my $user = {
		server => $server,
		nick => $nick,
		id => int $index
	};
	push(@queue, $user);
}
sub xdcc_list {
	my ($server, $index, $nick) = @_;
	if (scalar @files == 0) {
		$server->send_message( $nick, $m->{'no_files_offered'}, 1 );
		return;
	}
	my $msg, $file;
	for (my $n = 0; $n < @files ; ++$n) {
		$msg = "[" . ($n+1) . "] " . $files[$n]->{fn} . " ... " . $files[$n]->{desc};
		$server->send_message( $nick, $msg, 1 );
	}
	$msg = (scalar @files) . " file" . ( scalar @files == 1 ? "" : "s" );
	$server->send_message( $nick, $msg, 1 );
}
sub xdcc_queue {
	my ($server, $nick) = @_;
	if (scalar @queue == 0) {
		$server->send_message( $nick, $m->{'queue_is_empty'}, 1 );
		return
	}
	my $msg;
	for (my $n = 0; $n < @queue; ++$n) {
		if ($queue[$n]->{nick} == $nick) {
			$msg = "You are #" . ($n+1) . ", waiting for " . $files->{$queue[$n]->{id}}->{fn};
			$server->send_message( $nick, $msg, 1 );
			# break
		}
	}
	$msg = (scalar @files) . " in queue";
	$server->send_message( $nick, $msg, 1 );
}
sub xdcc_send {
	my ($server, $index, $nick) = @_;
	my $file = $files[$index];
	my $path = $file->{path};
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_sending_file', $index, $nick, $file->{fn});
	$server->command("/DCC send $nick $path");
	$msg = "Sending you " . $file->{fn} . " ...!";
	$server->send_message( $nick, $msg, 1 );
}

# client stuff
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
	}
}
sub xdcc_add {
	my ($path, $desc) = @_;
	if (! -e $path) {
		Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_file_dne');
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
	
	push(@files, $file)

	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_added_file', $id+1, $fn);
}
sub xdcc_del {
	my ($id) = @_;
	$id = (int $id) - 1;
	my $file = $files[$id];

	splice(@files, $id, 1);

	for (my $n = @queue; $n >= 0; --$n) {
		if ($queue[$n]->{id} == $id) {
			# send a message to the user that the file is no longer being offered
			splice(@queue, $n, 1);
		}
		else if ($queue[$n]->{id} > $id) {
			--$queue[$n]->{id};
		}
	}

	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_removed_file', $id+1, $file->{fn});
}
sub xdcc_reset {
	@files = ();
	@queue = ();
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_reset');
}
sub xdcc_help {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_help', $help);
}

sub xdcc {
	my ($cmd, $fn, $desc) = split (" ", $_[0], 3);

	$cmd = lc($cmd);

	switch ($cmd) {
		case "-add"   { xdcc_add($fn, desc) }
		case "-del"   { xdcc_remove($fn) }
		case "-list"  { xdcc_report() }
		case "-reset" { xdcc_reset() }
		case "-help"  { xdcc_help() }
		else          { xdcc_report() }
	}
}

# listen for xdcc end/cancel/close
Irssi::signal_add('default ctcp msg', 'ctcp_reply');
Irssi::command_bind('xdcc', 'xdcc');
Irssi::command_set_options('xdcc','add del list reset help');
Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'loaded', $IRSSI{name}, $VERSION, $IRSSI{authors});
