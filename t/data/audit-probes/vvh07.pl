my $x = 1; my @r = eval { die "z\n"; (7, 8) }; print scalar(@r), "$@";
