my $x=1; sub f { return \$_[0] } ${f($x)}=5; print "$x\n";
