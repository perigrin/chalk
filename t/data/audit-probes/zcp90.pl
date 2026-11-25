my @a=(1,2); my @b=(3); my $f=0; my @c=($f ? @a : @b); $b[0]=9; print "@c\n";
