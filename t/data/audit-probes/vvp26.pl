my @a = (1,2); sub f { my $r = \$a[-2]; $$r = 5; $_[0] } print f($a[0]), "\n";
