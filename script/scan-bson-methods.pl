#!/usr/bin/env perl
# ABOUTME: Scans .pm files through B::SoN and reports which methods it can translate.
# ABOUTME: Used during Phase A to identify comparison overlap with Chalk.

use 5.42.0;
use utf8;

my $son_lib = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $perl = $^X;

my @dirs = @ARGV ? @ARGV : ('lib/Chalk/IR');
my @files;
for my $dir (@dirs) {
    push @files, glob("$dir/*.pm");
}

for my $file (sort @files) {
    # Extract package name from file path
    my $pkg = $file;
    $pkg =~ s{^lib/}{};
    $pkg =~ s{/}{::}g;
    $pkg =~ s{\.pm$}{};

    my $cmd = "$perl -Ilib -I$son_lib -MO=SoN,json,package=$pkg $file 2>/dev/null";
    my $output = `$cmd`;
    my $exit = $? >> 8;

    if ($exit != 0 || !$output) {
        say "FAIL (B::SoN error) $file";
        next;
    }

    require JSON::PP;
    my $data = eval { JSON::PP->new->decode($output) };
    unless (defined $data) {
        say "FAIL (invalid JSON) $file";
        next;
    }

    my @methods = sort keys $data->{methods}->%*;
    say "OK (" . scalar(@methods) . " methods) $file";
    if ($ENV{VERBOSE}) {
        say "  $_" for @methods;
    }
}
