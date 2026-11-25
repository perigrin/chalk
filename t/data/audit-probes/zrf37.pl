my @a=({n=>1}); my @b=@a; $b[0]{n}=5; $b[0]={n=>7}; print "$a[0]{n}$b[0]{n}\n";
