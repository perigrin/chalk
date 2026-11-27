sub f { my $o = $_[0]; $_[1]->(); "$o$_[0]" } my %h = (k=>1); print f($h{k}, sub { $h{k} = 5 }), "\n";
