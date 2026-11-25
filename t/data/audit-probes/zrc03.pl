sub f { my %h; $h{$_[0]}=1; f($_[0]-1) if $_[0]; join ",", sort keys %h } print f(2), "\n";
