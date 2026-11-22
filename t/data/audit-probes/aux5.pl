our $g=1; eval { local $g=2; my $s = "abc"; my $r = \$s; my @a = @$r; print "in\n" }; print "$g\n";
