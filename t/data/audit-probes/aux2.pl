our $g=1; eval { local $g=2; my $z = @ARGV; my $x = sqrt($z - 1); print "in\n" }; print "$g\n";
