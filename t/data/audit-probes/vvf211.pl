our $t = 0; sub c { $t = 3; 2 } my $s = ++$t . c(); print "$s\n";
