my @a=(1,2); my $r = \$a[0]; my $x = $a[0]; $$r = 5; print "$x $a[0]\n";
