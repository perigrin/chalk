sub f { $_[0] = [1,2]; $_[1] = {a=>1} } my ($x,%h); f($x, $h{n}); print scalar(@$x), ref($h{n}), "\n";
