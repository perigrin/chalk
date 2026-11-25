my $x=1; my ($p,$q)=(\$x,\$x); $$p++; $$q*=5; print "$x\n";
