my @a = (1,2); my $r = \$a[0]; sub f { $$r = 5; $_[0] } print f($a[0]), "\n";
