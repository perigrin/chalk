my @a=(1,2,3); sub n { @a=(); 0 } my $r = n() + @a; print "$r\n";
