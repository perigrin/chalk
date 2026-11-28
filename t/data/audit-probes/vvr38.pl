my @a = (1,2,3); sub el { \$_[0] } my $r = el($a[1]); @a = reverse @a; $$r = 9; print "@a\n";
