sub f { my $r = \$_[0]; $$r .= "b"; $_[0] } my $s="a"; print f($s), $s, "\n";
