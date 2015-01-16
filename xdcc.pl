#!/usr/bin/perl -w

use strict;
use Irssi;
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

my @files;
my @queue;

my $queue_max = 10;

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

	'xdcc_sending_file',   '[%_XDCC:%_] Sending the file [$0] %_$2%_ to %_$1%_',
	'xdcc_no_files',       '[%_XDCC:%_] No files offered',
	'xdcc_print_file',     '[%_XDCC:%_] [%_$0%_] %_$1%_ ... %_$2%_',
	'xdcc_queue_empty',    '[%_XDCC:%_] The queue is currently empty',
	'xdcc_hr',             '[%_XDCC:%_] ----',
	'xdcc_print_queue',    '[%_XDCC:%_] $0. $1 - [$2] $3',
	'xdcc_file_not_found', '[%_XDCC:%_] File does not exist',
	'xdcc_added_file',     '[%_XDCC:%_] Added [$0] $1',
	'xdcc_removed_file',   '[%_XDCC:%_] Removed [$0] $1',
	'xdcc_reset',          '[%_XDCC:%_] Reset!',
	'xdcc_log',            '[%_XDCC:%_] $0',

	'xdcc_help', '$0',
	'loaded', '%R>>%n %_Scriptinfo:%_ Loaded $0 version $1 by $2.'
]);

my $messages = {
	'queue_is_full'    => "The XDCC queue is currently full.",
	'no_files_offered' => "Sorry there's no warez today",
	'queue_is_empty'   => "The XDCC queue is currently empty.",

	'file_entry'       => '[%d] %s ... %s',
	'file_count'       => '%d file%s',
	'in_queue'         => 'You are #%d in queue, waiting for %s',
	'queue_length'     => '%d request%s in queue',
	'sending_file'     => 'Sending you %s ...!',
};

my $ctcp_version = 'BlAaaGhhee kHaLed RuLez l0l u0.1';

sub ctcp_reply {
	my ($server, $data, $nick, $address, $target) = @_;

	my ($ctcp, $cmd, $index) = split (" ", lc($data), 3);
	
	if ($ctcp eq "version") {
		$server->command("^NCTCP $nick $data $ctcp_version");
		Irssi::signal_stop();
	}
	elsif ($ctcp ne "xdcc") { return; }
	
	   if ($cmd eq "get")   { xdcc_enqueue($server, $nick, $index) }
	elsif ($cmd eq "send")  { xdcc_enqueue($server, $nick, $index) }
	elsif ($cmd eq "list")  { xdcc_list($server, $nick) }
	elsif ($cmd eq "queue") { xdcc_queue($server, $nick) }

	Irssi::signal_stop();
}
sub xdcc_message {
	my ($server, $nick, $msgname, @params) = @_;
	my $msg = $messages->{$msgname};
	$msg =~ s/%_/\x002/g;
	$msg =~ s/%-/\x003/g;
	$msg = sprintf $msg, @params;
	$server->send_message( $nick, $msg, 1 );
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

	if (@queue == 0) {
		return xdcc_send($request);
	}
	elsif (@queue > $queue_max) {
		xdcc_message( $server, $nick, 'queue_is_full' );
		return;
	}
	push(@queue, $request);
	xdcc_queue();
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
}
sub xdcc_queue {
	my ($server, $nick) = @_;
	if (scalar @queue == 0) {
		xdcc_message( $server, $nick, 'queue_is_empty' );
		return
	}
	my $msg;
	for (my $n = 0; $n < @queue; ++$n) {
		if ($queue[$n]->{nick} == $nick) {
			xdcc_message( $server, $nick, 'in_queue', $n+1, $files[$queue[$n]->{id}]->{fn} )
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
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_sending_file', $id, $nick, $file->{fn});
	$server->command("/DCC send $nick $path");
	xdcc_message( $server, $nick, 'sending_file', $file->{fn} )
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
	if (substr($path, 0, 1) eq "~") {
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

	splice(@files, $id, 1);

	for (my $n = @queue; $n >= 0; --$n) {
		if ($queue[$n]->{id} == $id) {
			# send a message to the user that the file is no longer being offered
			splice(@queue, $n, 1);
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
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_reset');
}
sub xdcc_help {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_help', $help);
}

sub xdcc {
	my ($cmd, $fn, $desc) = split (" ", $_[0], 3);

	$cmd = lc($cmd);

	   if ($cmd eq "-add")   { xdcc_add($fn, $desc) }
	elsif ($cmd eq "-del")   { xdcc_remove($fn) }
	elsif ($cmd eq "-list")  { xdcc_report() }
	elsif ($cmd eq "-reset") { xdcc_reset() }
	elsif ($cmd eq "-help")  { xdcc_help() }
	 else                    { xdcc_report() }
}
sub dcc_created {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc created');
}
sub dcc_destroyed {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc destroyed');
	if (@queue == 0) { return; }
	my $request = shift @queue;
	xdcc_send($request);
}
sub dcc_connected {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc connected');
}
sub dcc_rejecting {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc rejecting');
}
sub dcc_closed {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'xdcc_log', 'dcc closed');
}

# listen for xdcc end/cancel/close
Irssi::signal_add('dcc created',      'dcc_created');
Irssi::signal_add('dcc destroyed',    'dcc_destroyed');
Irssi::signal_add('dcc connected',    'dcc_connected');
Irssi::signal_add('dcc rejecting',    'dcc_rejecting');
Irssi::signal_add('dcc closed',       'dcc_closed');
Irssi::signal_add('default ctcp msg', 'ctcp_reply');
Irssi::command_bind('xdcc', 'xdcc');
Irssi::command_set_options('xdcc','add del list reset help');
Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'loaded', $IRSSI{name}, $VERSION, $IRSSI{authors});
