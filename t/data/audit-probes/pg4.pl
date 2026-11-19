our $g = 1; sub rd { $g } my $a = $g; $g = 2; my $b = rd(); $g = 3; print "$a$b$g\n";
