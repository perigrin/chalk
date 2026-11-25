sub set { my $r=shift; $$r=5 } my $x=1; set(\$x); print "$x\n";
