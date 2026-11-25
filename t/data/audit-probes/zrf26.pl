sub set { my $r=shift; $$r=5 } my @a=(1,2); set(\$a[1]); print "@a\n";
