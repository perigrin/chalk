my %h=(l=>[1,2]); sub z { $h{l}[1]=7 } for my $x (@{$h{l}}) { z(); print $x } print "\n";
