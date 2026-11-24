srand(7); my $a = int rand 1000; my $b = int rand 1000; srand(7); my $c = int rand 1000;
print $a == $c ? "a=c " : "a!=c ", $a == $b ? "a=b\n" : "a!=b\n";
