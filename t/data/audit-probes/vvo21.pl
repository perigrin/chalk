my %h = (a=>1,b=>2); sub z { $h{a} = 9; 0 } my @l = ((@h{qw(a b)} = (7,8)), z()); print "@l\n";
