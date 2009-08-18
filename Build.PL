use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Net::Squid::ReverseProxy',
    license             => 'perl',
    dist_author         => 'Jeff Pang <JeffHua@aol.com>',
    dist_version_from   => 'lib/Net/Squid/ReverseProxy.pm',
    requires => {
        'Test::More' => 0,
        'version'    => 0,
    },
    add_to_cleanup      => [ 'Net-Squid-ReverseProxy-*' ],
);

$builder->create_build_script();
