our %x = (k=>1); sub c { $x{k} = 3; 2 } my $s = $x{k} . c(); print "$s\n";
