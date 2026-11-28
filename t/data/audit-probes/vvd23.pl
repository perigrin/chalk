my %h = (a=>1,b=>2); ($h{a}, $h{b}) = ($h{b}, $h{a}); print "$h{a}$h{b}\n";
