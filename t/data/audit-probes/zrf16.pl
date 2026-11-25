my ($x,$y)=(1,2); my @r=(\$x,\$y); ${$r[$_]}*=2 for 0,1; print "$x$y\n";
