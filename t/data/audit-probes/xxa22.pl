sub f { $_[0]{k} = 5; 1 } my %h=(k=>1); my @l = ($h{k}, f(\%h), $h{k}); print "@l\n";
