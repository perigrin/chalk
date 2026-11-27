our $x = "b"; sub c { $x = "a"; "c" } my %h = (a=>1,b=>2,c=>3); my @l = @h{$x, c()}; print "@l\n";
