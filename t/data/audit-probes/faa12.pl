my $x=1; my @a=(\$x,\$x); ${$a[0]}++; print ${$a[1]},"\n";
