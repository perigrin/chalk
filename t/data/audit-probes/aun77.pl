our $g=1; eval { local $g = 2; my $d = @ARGV; my $q = 1/$d; print "in\n" }; print "$g\n";
