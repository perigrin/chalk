our $g=1; eval { local $g=2; my $z = @ARGV; my $x = log($z); print "in\n" }; print "$g\n";
