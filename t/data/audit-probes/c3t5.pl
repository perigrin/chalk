sub f { srand($_[0]); return rand }
my $x = f(3); my $y = rand; my $z = f(3);
print $x == $z ? "x=z " : "x!=z ", $x == $y ? "x=y\n" : "x!=y\n";
