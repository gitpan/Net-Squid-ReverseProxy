package Net::Squid::ReverseProxy;

use strict;
use Carp qw/croak/;

use vars qw/$VERSION/;
$VERSION = '0.01';

sub new {

    my $class = shift;
    my %arg = @_;
    my $squid = $arg{'squid'};
    my $cfg = $arg{'squid_conf'};

    unless (-f $cfg && -w $cfg ) {
	croak "squid config file doesn't exist or isn't writable";
    }

    unless (-f $squid && -x $squid ) {
	croak "squid program doesn't exist or isn't executable";
    }

    bless { 'squid' => $squid,
	    'squid_conf' => $cfg,
	  }, $class;
}

sub init_squid_for_reverseproxy {

    my $self = shift;
    my %arg = @_;

    my $cfg = $self->{'squid_conf'};
    my $squid = $self->{'squid'};

    my $cache_mem = $arg{'cache_mem'} || 50;
    my $maximum_object_size = $arg{'maximum_object_size'} || 2048;
    my $maximum_object_size_in_memory = $arg{'maximum_object_size_in_memory'} || 64;
    my $cache_dir_size = $arg{'cache_dir_size'} || 50;
    my $visible_hostname = $arg{'visible_hostname'} || 'localhost.localdomain';

    if ($arg{'cache_dir'} ) {
        my $uid = (stat $arg{'cache_dir'})[4];
        my $user = (getpwuid $uid)[0];

	if ($user ne 'nobody') {
	    croak "init failed, $arg{'cache_dir'} must be owned by nobody";
	} 
    }

    my $cache_dir = $arg{'cache_dir'} || '/tmp/squidcache';

    my $module_dir = $INC{'Net/Squid/ReverseProxy.pm'};
    $module_dir =~ s/\.pm$//;

    my @cfg;

    open HD, "$module_dir/squidcfg" or croak "can't open template file $!";

    while (<HD>) {

	push @cfg,$_;

	if (/ARG INPUT BEGIN/) {
	    push @cfg,
	      "cache_mem $cache_mem MB\n",
	      "maximum_object_size $maximum_object_size KB\n",
	      "maximum_object_size_in_memory $maximum_object_size_in_memory KB\n",
	      "cache_dir ufs $cache_dir $cache_dir_size 16 256\n",
	      "visible_hostname $visible_hostname\n";
        }
    }
    close HD;

    open HD, $cfg or croak $!;
    my @oldcfg = <HD>;
    close HD;

    open HDW,">",$cfg or croak $!;
    print HDW for @cfg;
    close HDW;

    system "$squid -k kill >/dev/null 2>&1";
    system "$squid -z >/dev/null 2>&1 && $squid -D";

    if ($? == 0) {
	return 1;

    } else {

        open HDW,">",$cfg or croak $!;
        print HDW for @oldcfg;
        close HDW;

	croak "init failed, can't run 'squid -z' then 'squid -D'";
    }
}

sub add_dstdomain_proxy {

    my $self = shift;
    my %arg = @_;

    my $cfg = $self->{'squid_conf'};
    my $squid = $self->{'squid'};

    my $site_dst = $arg{'dstdomain'};
    my @ip = @{$arg{'original_server'}};
    my $algor = $arg{'load_balance'} || '';

    unless ($site_dst && @ip) {
	return undef;
    }

    my @newconf;
    my %cache_peer_access;

    $cache_peer_access{'origin'} = 'origin_0_0';
    open HD, $cfg or croak $!;
    while(<HD>) {
        last if /SITE END/;
        if (/^cache_peer_access/) {
            $cache_peer_access{'origin'} = (split)[1];
        }
    }
    close HD;

    my $idmax = (split /\_/, $cache_peer_access{'origin'})[-2];
    $idmax++;

    open HD, $cfg or croak $!;
    while(<HD>) {

        if (/SITE END/) {
            my $int = 1;
            for my $ip (@ip) {
                my ($site_ip,$site_port) = split/\:/,$ip;
                $site_port ||= 80;
                push @newconf, 
                "cache_peer $site_ip parent $site_port 0 no-query originserver name=origin_${idmax}_$int $algor\n";
                $int++;
            }

            push @newconf,"acl service_$idmax dstdomain $site_dst\n";

            for my $int (1 .. scalar(@ip) ) {
                push @newconf, "cache_peer_access origin_${idmax}_$int allow service_$idmax\n";
            }
        }

        push @newconf,$_;
    }
    close HD;

    open HD, $cfg or croak $!;
    my @oldcfg = <HD>;
    close HD;

    open HDW, ">", $cfg or croak $!;
    print HDW for @newconf;
    close HDW;

    my @err = `$squid -k reconfig 2>&1`;
    if (@err) {

        open HDW,">",$cfg or croak $!;
        print HDW for @oldcfg;
        close HDW;

	system "$squid -k reconfig >/dev/null 2>&1";
        return undef;

    } else {
        return 1;
    }
}

sub remove_dstdomain_proxy {

    my $self = shift;
    my $domain = shift || return;

    my $cfg = $self->{'squid_conf'};
    my $squid = $self->{'squid'};

    $domain = quotemeta($domain);

    my @id;
    open HD,$cfg or croak $!;
    while(<HD>) {
	if (/^acl\s+service_(\d+)\s+dstdomain\s+$domain/) {
	    push @id, $1;
	}
    }
    close HD;

    my @cfg;
    open HD,$cfg or croak $!;
    while(<HD>) {
	my $next = 0;
	for my $id (@id) {
	    $next=1 if (/origin_${id}_/ || /service_${id}\s+/);
	}
	next if $next;
        push @cfg,$_;
    }
    close HD;
    
    open HD, $cfg or croak $!;
    my @oldcfg = <HD>;
    close HD;

    open HDW, ">", $cfg or croak $!;
    print HDW for @cfg;
    close HDW;

    my @err = `$squid -k reconfig 2>&1`;
    if (@err) {

        open HDW,">",$cfg or croak $!;
        print HDW for @oldcfg;
        close HDW;

	system "$squid -k reconfig >/dev/null 2>&1";
        return undef;

    } else {
        return 1;
    }
}


1;


=head1 NAME

Net::Squid::ReverseProxy - setup a HTTP reverse proxy with Squid

=head1 VERSION

Version 0.01


=head1 SYNOPSIS

    use Net::Squid::ReverseProxy;

    my $squid = Net::Squid::ReverseProxy->new(
                     'squid' => '/path/to/squid',
                     'squid_conf' => '/path/to/squid.conf');

    $squid->init_squid_for_reverseproxy;
    sleep 1;

    $squid->add_dstdomain_proxy('dstdomain' => 'www.example.com',
                           'original_server' => ['192.168.1.100'])
            or die "can't add dstdomain\n";

    $squid->add_dstdomain_proxy('dstdomain' => 'www.example.com',
                          'original_server' => ['192.168.1.100',
                                                '192.168.1.200:8080'],
			     'load_balance' => 'round-robin')
            or die "can't add dstdomain\n";

    $squid->remove_dstdomain_proxy('www.example.com')
            or die "can't remove dstdomain\n";


=head1 METHODS

=head2 new()

Create an object, please specify the full path of both squid 
executable program and squid config file.

   my $squid = Net::Squid::ReverseProxy->new(
                     'squid' => '/path/to/squid',
                     'squid_conf' => '/path/to/squid.conf');

Before using this module, you must have squid installed in
the system. You could get the latest source from its official
website squid-cache.org, then compile and install it.


=head2 init_squid_for_reverseproxy()

Warnning: the config file will be overwritten by this method, you 
should execute the method only once at the first time of using this 
module. It's used to initialize the setting for squid reverse proxy. 

Could pass the arguments like below to this method as well:

    $squid->init_squid_for_reverseproxy(
      'cache_mem' => 200,
      'maximum_object_size' => 4096,
      'maximum_object_size_in_memory' => 64,
      'cache_dir_size' => 1024,
      'visible_hostname' => 'squid.domain.com',
      'cache_dir' => '/data/squidcache',
    );

cache_mem: how large memory (MB) squid will use for cache, default 50

maximum_object_size: the maximum object size (KB) squid will cache with,
default 2048

maximum_object_size_in_memory: the maximum object size (KB) squid will
cache with in memory, default 64

cache_dir_size: how large disk (MB) squid will use for cache, default 50

visible_hostname: visiable hostname, default localhost.localdomain

cache_dir: path to cache dir, default /tmp/squidcache


After calling this method, you MUST sleep at least 1 second to wait for 
squid finish starting up before any further operation.

If initialized correctly, it will make squid run and listen on TCP port
80 for HTTP requests. If initialized failed, you may check /tmp/cache.log
for details.


=head2 add_dstdomain_proxy()

Add a reverse proxy rule based on dstdomain (destination domain).
For example, you want to reverse-proxy the domain www.example.com,
whose backend webserver is 192.168.1.100, then do:

    $squid->add_dstdomain_proxy('dstdomain' => 'www.example.com',
                          'original_server' => ['192.168.1.100']);

Here 'dstdomain' means destination domain, 'original_server' means backend
webserver. If you have two backend webservers, one is 192.168.1.100, whose 
http port is 80 (the default), another is 192.168.1.200, whose http port is 
8080, then do:

    $squid->add_dstdomain_proxy('dstdomain' => 'www.example.com',
                          'original_server' => ['192.168.1.100',
                                                '192.168.1.200:8080'],
			     'load_balance' => 'round-robin');

Here 'load_balance' specifies an algorithm for balancing http requests among
webservers. The most common used algorithms are round-robin and sourcehash.
The latter is used for session persistence mostly. See squid.conf.default
for details.


=head2 remove_dstdomain_proxy()

Remove reverse proxy rule(s) for the specified destination domain.

    $squid->remove_dstdomain_proxy('www.example.com');


=head1 AUTHOR

Jeff Pang <pangj@arcor.de>


=head1 BUGS/LIMITATIONS

If you have found bugs, please send mail to <pangj@arcor.de>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::Squid::ReverseProxy

For the general knowledge of installing and setup squid, please reference
documents and wiki on squid-cache.org, or subscribe to squid user's mailing
list, or, you can email me in private. For Chinese you could read online the
Chinese version of "Squid: The Definitive Guide" translated by me:

    http://home.arcor.de/mailerstar/jeff/squid/


=head1 COPYRIGHT & LICENSE

Copyright 2009 Jeff Pang, all rights reserved.

This program is free software; you can redistribute it and/or modify 
it under the same terms as Perl itself.

