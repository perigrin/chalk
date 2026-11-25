my %h=(a=>{n=>1}); my $e=$h{a}; delete $h{a}; $e->{n}++; print $e->{n}, scalar(keys %h), "\n";
