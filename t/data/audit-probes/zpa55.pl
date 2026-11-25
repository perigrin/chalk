my %h=(a=>1,b=>2); for (values %h) { $_*=2 } print join(",", map { $h{$_} } sort keys %h), "\n";
