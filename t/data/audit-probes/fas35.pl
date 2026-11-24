my @a=(1,2,3); sub n { shift @a } my $r = $a[0] . n() . $a[0]; print "$r\n";
