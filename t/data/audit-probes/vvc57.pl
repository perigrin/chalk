package P; our $v = 1; sub get { $v } package main; my $y = 2; *P::v = \$y; $y = 5; print P::get(), "\n";
