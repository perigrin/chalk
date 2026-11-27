our $x = 1; sub c { $x = 5; 1 } my @a = (10,20,30,40,50,60); my @l = @a[$x, c()]; print "@l\n";
