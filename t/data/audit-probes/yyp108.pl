my @a=(1,2); my @c=(3); my $c=1; my @b=(($c ? @a : @c), $a[0]=9); print "@b\n";
