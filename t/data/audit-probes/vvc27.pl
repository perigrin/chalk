our $x = 1; sub rd { $x } my $y = 7; *x = \$y; $y = 8; print rd(), "\n";
