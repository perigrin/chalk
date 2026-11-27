my @a=(3,1,2); sub k { $_[0] * -1 } my @s = sort { k($a) <=> k($b) } @a; print "@s\n";
