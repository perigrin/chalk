our $x = 1; my $i = 0; do { local $x = 5; $i++ } while ($i < 2); print "$x\n";
