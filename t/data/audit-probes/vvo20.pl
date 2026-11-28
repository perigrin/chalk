my %h = (a=>1,b=>2); my @l = ((($h{a}, $h{b}) = (7,8)), $h{a} = 9); print "@l\n";
