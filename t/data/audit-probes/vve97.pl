my %h = (k=>1); my $key = "k"; sub f { $h{$key} = 5; $_[0] } print f($h{k}), "\n";
