sub set { ${$_[0]} = 4 } my $x = 1; set(\$x); print "$x\n";
