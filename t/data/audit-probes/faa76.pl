sub fill { my $r=shift; @$r=(7,8) } my @a=(1); my $n=@a; fill(\@a); print $n, scalar(@a), "$a[0]\n";
