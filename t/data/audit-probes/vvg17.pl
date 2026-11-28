my $x = 1; sub set { ${$_[0]} = $_[1] } set(\$x, 5); print "$x\n";
