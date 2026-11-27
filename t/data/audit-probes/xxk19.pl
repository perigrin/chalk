my @a = ("ab","cd"); s/(.)(.)/$2$1/ for @a; print "@a\n";
