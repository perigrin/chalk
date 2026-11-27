my @a=("a","b"); s/$/!/ for @a; tr/a-b/A-B/ for @a; print "@a\n";
