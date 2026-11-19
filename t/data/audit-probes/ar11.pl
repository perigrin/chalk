sub f { $_[0] .= "!" } my @a = ("a"); f($a[0]); f($a[5]); print scalar(@a), " $a[0] $a[5]\n";
