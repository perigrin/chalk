our $g=1; eval { local $g=2; my $x = 1; my $r = \$x; my %h = %$r; print "in\n" }; print "$g\n";
