# ABOUTME: The LLVM runtime every T2 module links: its types, declarations, constants and
# ABOUTME: the t2_* functions, as .ll text (prelude) the printer puts at the module's head.
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Runtime;

# The runtime a slice-1 module calls: %Str is { i8*, i64 }; %Slot is a tag
# (0 undef, 1 Int, 2 Num, 3 Str) and an i64 payload (a Num's bits, a Str's
# heap pointer). Numbers print as perl prints them: %.15g, Inf, -Inf, NaN.
sub prelude { return <<'LL' }
%Str = type { i8*, i64 }
%Slot = type { i8, i64 }
declare i32 @snprintf(i8*, i64, i8*, ...)
declare i8* @malloc(i64)
declare i8* @memcpy(i8*, i8*, i64)
declare i8* @getenv(i8*)
declare i64 @strlen(i8*)
declare double @strtod(i8*, i8**)
declare i64 @write(i32, i8*, i64)
@fmt_g = private unnamed_addr constant [6 x i8] c"%.15g\00"
@fmt_d = private unnamed_addr constant [4 x i8] c"%ld\00"
@lit_inf = private unnamed_addr constant [4 x i8] c"Inf\00"
@lit_ninf = private unnamed_addr constant [5 x i8] c"-Inf\00"
@lit_nan = private unnamed_addr constant [4 x i8] c"NaN\00"
@lit_one = private unnamed_addr constant [2 x i8] c"1\00"
@lit_zero = private unnamed_addr constant [2 x i8] c"0\00"
define internal %Str @t2_str(i8* %p, i64 %n) {
  %a = insertvalue %Str undef, i8* %p, 0
  %b = insertvalue %Str %a, i64 %n, 1
  ret %Str %b
}
define internal void @t2_print(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  call i64 @write(i32 1, i8* %p, i64 %n)
  ret void
}
define internal void @t2_eprint(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  call i64 @write(i32 2, i8* %p, i64 %n)
  ret void
}
; THE CALL STACK caller reads: three slots a frame (package, file, line),
; pushed by each call of a sub while the program reads caller.
@t2_frames = internal global %Array* null
define internal %Array* @t2_frames_get() {
  %f = load %Array*, %Array** @t2_frames
  %z = icmp eq %Array* %f, null
  br i1 %z, label %mk, label %ok
mk:
  %n = call %Array* @t2_new_array()
  store %Array* %n, %Array** @t2_frames
  ret %Array* %n
ok:
  ret %Array* %f
}
define internal void @t2_frame_push(%Str %p, %Str %f, i64 %l) {
  %a = call %Array* @t2_frames_get()
  %sp = call %Slot @t2_box_str(%Str %p)
  call void @t2_apush_d(%Array* %a, %Slot %sp)
  %sf = call %Slot @t2_box_str(%Str %f)
  call void @t2_apush_d(%Array* %a, %Slot %sf)
  %sl = call %Slot @t2_box_i64(i64 %l)
  call void @t2_apush_d(%Array* %a, %Slot %sl)
  ret void
}
define internal void @t2_frame_pop() {
  %a = call %Array* @t2_frames_get()
  %x = call %Slot @t2_apop_d(%Array* %a)
  %y = call %Slot @t2_apop_d(%Array* %a)
  %z = call %Slot @t2_apop_d(%Array* %a)
  ret void
}
; t2_frame_at(n) -> the index of frame n's package (n up from the innermost), or -1.
define internal i64 @t2_frame_at(i64 %n) {
  %a = call %Array* @t2_frames_get()
  %len = call i64 @t2_alen_d(%Array* %a)
  %n1 = add i64 %n, 1
  %k = mul i64 %n1, 3
  %neg = icmp slt i64 %n, 0
  %short = icmp slt i64 %len, %k
  %no = or i1 %neg, %short
  %base = sub i64 %len, %k
  %r = select i1 %no, i64 -1, i64 %base
  ret i64 %r
}
define internal %Array* @t2_caller(i64 %n) {
  %r = call %Array* @t2_new_array()
  %i = call i64 @t2_frame_at(i64 %n)
  %no = icmp slt i64 %i, 0
  br i1 %no, label %none, label %some
some:
  %a = call %Array* @t2_frames_get()
  %p = call %Slot @t2_aget_d(%Array* %a, i64 %i)
  call void @t2_apush_d(%Array* %r, %Slot %p)
  %i1 = add i64 %i, 1
  %f = call %Slot @t2_aget_d(%Array* %a, i64 %i1)
  call void @t2_apush_d(%Array* %r, %Slot %f)
  %i2 = add i64 %i, 2
  %l = call %Slot @t2_aget_d(%Array* %a, i64 %i2)
  call void @t2_apush_d(%Array* %r, %Slot %l)
  br label %none
none:
  ret %Array* %r
}
define internal %Slot @t2_caller_pkg(i64 %n) {
  %i = call i64 @t2_frame_at(i64 %n)
  %no = icmp slt i64 %i, 0
  br i1 %no, label %none, label %some
some:
  %a = call %Array* @t2_frames_get()
  %p = call %Slot @t2_aget_d(%Array* %a, i64 %i)
  ret %Slot %p
none:
  ret %Slot zeroinitializer
}
; substr(s, off[, len]): perl's translate_substr_offsets (pp.c), in signed ints --
; a negative offset counts from the end (still before it: clamped, unless the
; end is too). The bytes copied, NUL-ended. OUTSIDE THE STRING perl answers
; undef with a warning under `use warnings`, which T2 does not know: stopped
; at run time (exit 255), as the fallback does, not answered half right.
@lit_substr_out = private unnamed_addr constant [47 x i8] c"substr outside of string: stopped (chalk, T2)\0A\00"
define internal %Slot @t2_substr(%Str %s, i64 %off, i64 %len, i1 %has) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %oneg = icmp slt i64 %off, 0
  %npos = icmp sgt i64 %n, 0
  %adj = and i1 %oneg, %npos
  %offn = add i64 %off, %n
  %p1 = select i1 %adj, i64 %offn, i64 %off
  %past = icmp sgt i64 %p1, %n
  br i1 %past, label %undef, label %ends
ends:
  %lneg = icmp slt i64 %len, 0
  %fromend = add i64 %n, %len
  %p1neg = icmp slt i64 %p1, 0
  %p1len = add i64 %p1, %len
  %room = sub i64 %n, %p1
  %toolong = icmp sgt i64 %len, %room
  %fwd = select i1 %toolong, i64 %n, i64 %p1len
  %pos2 = select i1 %p1neg, i64 %p1len, i64 %fwd
  %withlen = select i1 %lneg, i64 %fromend, i64 %pos2
  %p2a = select i1 %has, i64 %withlen, i64 %n
  %p2neg = icmp slt i64 %p2a, 0
  %both = and i1 %p2neg, %p1neg
  br i1 %both, label %undef, label %clamp
clamp:
  %p2b = select i1 %p2neg, i64 0, i64 %p2a
  %p1b = select i1 %p1neg, i64 0, i64 %p1
  %under = icmp slt i64 %p2b, %p1b
  %p2c = select i1 %under, i64 %p1b, i64 %p2b
  %over = icmp sgt i64 %p2c, %n
  %p2 = select i1 %over, i64 %n, i64 %p2c
  %l = sub i64 %p2, %p1b
  %l1b = add i64 %l, 1
  %buf = call i8* @malloc(i64 %l1b)
  %src = getelementptr i8, i8* %p, i64 %p1b
  call i8* @memcpy(i8* %buf, i8* %src, i64 %l)
  %end = getelementptr i8, i8* %buf, i64 %l
  store i8 0, i8* %end
  %r = call %Str @t2_str(i8* %buf, i64 %l)
  %rs = call %Slot @t2_box_str(%Str %r)
  ret %Slot %rs
undef:
  call i64 @write(i32 2, i8* getelementptr ([47 x i8], [47 x i8]* @lit_substr_out, i64 0, i64 0), i64 46)
  call void @t2_run_ends()
  call void @exit(i32 255)
  unreachable
}
; substr(s, off, len, r): s with the part substr(s, off, len) names replaced by r
; -- the offsets t2_substr takes (which stopped already were they outside).
define internal %Slot @t2_substr_rep(%Str %s, i64 %off, i64 %len, %Str %r) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %rp = extractvalue %Str %r, 0
  %rn = extractvalue %Str %r, 1
  %oneg = icmp slt i64 %off, 0
  %npos = icmp sgt i64 %n, 0
  %adj = and i1 %oneg, %npos
  %offn = add i64 %off, %n
  %p1 = select i1 %adj, i64 %offn, i64 %off
  %lneg = icmp slt i64 %len, 0
  %fromend = add i64 %n, %len
  %p1neg = icmp slt i64 %p1, 0
  %p1len = add i64 %p1, %len
  %room = sub i64 %n, %p1
  %toolong = icmp sgt i64 %len, %room
  %fwd = select i1 %toolong, i64 %n, i64 %p1len
  %pos2 = select i1 %p1neg, i64 %p1len, i64 %fwd
  %p2a = select i1 %lneg, i64 %fromend, i64 %pos2
  %p2neg = icmp slt i64 %p2a, 0
  %p2b = select i1 %p2neg, i64 0, i64 %p2a
  %p1b = select i1 %p1neg, i64 0, i64 %p1
  %under = icmp slt i64 %p2b, %p1b
  %p2c = select i1 %under, i64 %p1b, i64 %p2b
  %over = icmp sgt i64 %p2c, %n
  %p2 = select i1 %over, i64 %n, i64 %p2c
  %tail = sub i64 %n, %p2
  %l0 = add i64 %p1b, %rn
  %l = add i64 %l0, %tail
  %l1 = add i64 %l, 1
  %buf = call i8* @malloc(i64 %l1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %p1b)
  %mid = getelementptr i8, i8* %buf, i64 %p1b
  call i8* @memcpy(i8* %mid, i8* %rp, i64 %rn)
  %dst = getelementptr i8, i8* %buf, i64 %l0
  %src = getelementptr i8, i8* %p, i64 %p2
  call i8* @memcpy(i8* %dst, i8* %src, i64 %tail)
  %end = getelementptr i8, i8* %buf, i64 %l
  store i8 0, i8* %end
  %str = call %Str @t2_str(i8* %buf, i64 %l)
  %box = call %Slot @t2_box_str(%Str %str)
  ret %Slot %box
}
; index(s, t, pos): the first place at or after pos (clamped into the string) t is, or -1.
define internal i64 @t2_index(%Str %s, %Str %t, i64 %pos0) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %q = extractvalue %Str %t, 0
  %m = extractvalue %Str %t, 1
  %pneg = icmp slt i64 %pos0, 0
  %pa = select i1 %pneg, i64 0, i64 %pos0
  %pbig = icmp sgt i64 %pa, %n
  %pos = select i1 %pbig, i64 %n, i64 %pa
  br label %loop
loop:
  %i = phi i64 [ %pos, %entry ], [ %i1, %next ]
  %e = add i64 %i, %m
  %fits = icmp sle i64 %e, %n
  br i1 %fits, label %cmp, label %none
cmp:
  %at = getelementptr i8, i8* %p, i64 %i
  %c = call i32 @memcmp(i8* %at, i8* %q, i64 %m)
  %eq = icmp eq i32 %c, 0
  br i1 %eq, label %found, label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
found:
  ret i64 %i
none:
  ret i64 -1
}
; END BLOCKS: the program's, in the order they run (t2_atexit adds one);
; t2_run_ends runs them once, at every way out -- the main line's end, an
; exit, a die (atexit(3) is not run by lli for an exit the program calls).
@t2_ends = internal global [64 x void ()*] zeroinitializer
@t2_nends = internal global i64 0
define internal void @t2_atexit(void ()* %f) {
  %n = load i64, i64* @t2_nends
  %p = getelementptr [64 x void ()*], [64 x void ()*]* @t2_ends, i64 0, i64 %n
  store void ()* %f, void ()** %p
  %n1 = add i64 %n, 1
  store i64 %n1, i64* @t2_nends
  ret void
}
define internal void @t2_run_ends() {
entry:
  %n = load i64, i64* @t2_nends
  store i64 0, i64* @t2_nends
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %p = getelementptr [64 x void ()*], [64 x void ()*]* @t2_ends, i64 0, i64 %i
  %f = load void ()*, void ()** %p
  call void %f()
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}
define internal void @t2_exit(i64 %v) {
  %c = trunc i64 %v to i32
  call void @t2_run_ends()
  call void @exit(i32 %c)
  unreachable
}
define internal %Str @t2_concat(%Str %x, %Str %y) {
  %xp = extractvalue %Str %x, 0
  %xn = extractvalue %Str %x, 1
  %yp = extractvalue %Str %y, 0
  %yn = extractvalue %Str %y, 1
  %n = add i64 %xn, %yn
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %xp, i64 %xn)
  %mid = getelementptr i8, i8* %buf, i64 %xn
  call i8* @memcpy(i8* %mid, i8* %yp, i64 %yn)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal %Str @t2_i64_str(i64 %v) {
  %buf = call i8* @malloc(i64 24)
  %f = getelementptr [4 x i8], [4 x i8]* @fmt_d, i64 0, i64 0
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 24, i8* %f, i64 %v)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal %Str @t2_num_str(double %v) {
entry:
  %nan = fcmp uno double %v, %v
  br i1 %nan, label %isnan, label %notnan
isnan:
  %pn = getelementptr [4 x i8], [4 x i8]* @lit_nan, i64 0, i64 0
  %rn = call %Str @t2_str(i8* %pn, i64 3)
  ret %Str %rn
notnan:
  %pinf = fcmp oeq double %v, 0x7FF0000000000000
  br i1 %pinf, label %ispinf, label %notpinf
ispinf:
  %pi = getelementptr [4 x i8], [4 x i8]* @lit_inf, i64 0, i64 0
  %ri = call %Str @t2_str(i8* %pi, i64 3)
  ret %Str %ri
notpinf:
  %ninf = fcmp oeq double %v, 0xFFF0000000000000
  br i1 %ninf, label %isninf, label %finite
isninf:
  %pm = getelementptr [5 x i8], [5 x i8]* @lit_ninf, i64 0, i64 0
  %rm = call %Str @t2_str(i8* %pm, i64 4)
  ret %Str %rm
finite:
  %zero = fcmp oeq double %v, 0.0
  br i1 %zero, label %iszero, label %nonzero
iszero:
  %pz = getelementptr [2 x i8], [2 x i8]* @lit_zero, i64 0, i64 0
  %rz = call %Str @t2_str(i8* %pz, i64 1)
  ret %Str %rz
nonzero:
  %buf = call i8* @malloc(i64 32)
  %f = getelementptr [6 x i8], [6 x i8]* @fmt_g, i64 0, i64 0
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 32, i8* %f, double %v)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal double @t2_str_num(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %n)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %d = call double @strtod(i8* %buf, i8** null)
  ret double %d
}
define internal i64 @t2_str_i64(%Str %s) {
  %n = call %Slot @t2_str_numslot(%Str %s)
  %i = call i64 @t2_slot_i64(%Slot %n)
  ret i64 %i
}
declare i64 @strtoll(i8*, i8**, i32)
; A STRING'S NUMBER, perl's way: its leading integer kept whole (strtoll)
; unless a fraction or exponent follows, else its double.
define internal %Slot @t2_str_numslot(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %n)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %ep = alloca i8*
  %i = call i64 @strtoll(i8* %buf, i8** %ep, i32 10)
  %e = load i8*, i8** %ep
  %none = icmp eq i8* %e, %buf
  br i1 %none, label %num, label %after
after:
  %c = load i8, i8* %e
  %dot = icmp eq i8 %c, 46
  %ee = icmp eq i8 %c, 101
  %eE = icmp eq i8 %c, 69
  %f1 = or i1 %dot, %ee
  %frac = or i1 %f1, %eE
  %max = icmp eq i64 %i, 9223372036854775807
  %min = icmp eq i64 %i, -9223372036854775808
  %edge = or i1 %max, %min
  %tonum = or i1 %frac, %edge
  br i1 %tonum, label %num, label %int
int:
  %si = call %Slot @t2_box_i64(i64 %i)
  ret %Slot %si
num:
  %d = call double @strtod(i8* %buf, i8** null)
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
define internal %Slot @t2_slot_numify(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %undef [ i8 1, label %same
                               i8 2, label %same
                               i8 3, label %str
                               i8 5, label %ref
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
same:
  ret %Slot %s
str:
  %v = extractvalue %Slot %s, 1
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %r = call %Slot @t2_str_numslot(%Str %sv)
  ret %Slot %r
undef:
  %z = call %Slot @t2_box_i64(i64 0)
  ret %Slot %z
ref:
  ; A REFERENCE AS A NUMBER is its address (perl's refaddr): == compares them.
  %ra = extractvalue %Slot %s, 1
  %rs = call %Slot @t2_box_i64(i64 %ra)
  ret %Slot %rs
}
define internal %Str @t2_bool_str(i1 %b) {
  %p = getelementptr [2 x i8], [2 x i8]* @lit_one, i64 0, i64 0
  %n = zext i1 %b to i64
  %r = call %Str @t2_str(i8* %p, i64 %n)
  ret %Str %r
}
define internal double @t2_bool_num(i1 %b) {
  %d = uitofp i1 %b to double
  ret double %d
}
define internal %Slot @t2_slot(i8 %t, i64 %v) {
  %a = insertvalue %Slot undef, i8 %t, 0
  %b = insertvalue %Slot %a, i64 %v, 1
  ret %Slot %b
}
define internal %Slot @t2_box_i64(i64 %v) {
  %s = call %Slot @t2_slot(i8 1, i64 %v)
  ret %Slot %s
}
; t2_cstr(s): s as a NUL-terminated C string (a copy).
; t2_ftdir(path): perl's -d -- 1 a directory, '' something else, undef nothing.
; t2_chdir(path): perl's chdir -- 1, or ''.
declare i8* @opendir(i8*)
declare i32 @closedir(i8*)
declare i32 @access(i8*, i32)
declare i32 @chdir(i8*)
define internal i8* @t2_cstr(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %c = call i8* @malloc(i64 %n1)
  call i8* @memmove(i8* %c, i8* %p, i64 %n)
  %e = getelementptr i8, i8* %c, i64 %n
  store i8 0, i8* %e
  ret i8* %c
}
define internal %Slot @t2_ftdir(%Str %s) {
entry:
  %c = call i8* @t2_cstr(%Str %s)
  %d = call i8* @opendir(i8* %c)
  %isdir = icmp ne i8* %d, null
  br i1 %isdir, label %dir, label %other
dir:
  call i32 @closedir(i8* %d)
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
other:
  %a = call i32 @access(i8* %c, i32 0)
  %there = icmp eq i32 %a, 0
  br i1 %there, label %file, label %none
file:
  %no = call %Str @t2_str(i8* getelementptr ([1 x i8], [1 x i8]* @t2_empty, i64 0, i64 0), i64 0)
  %nos = call %Slot @t2_box_str(%Str %no)
  ret %Slot %nos
none:
  %u = call %Slot @t2_slot(i8 0, i64 0)
  ret %Slot %u
}
define internal %Slot @t2_chdir(%Str %s) {
entry:
  %c = call i8* @t2_cstr(%Str %s)
  %r = call i32 @chdir(i8* %c)
  %ok = icmp eq i32 %r, 0
  br i1 %ok, label %yes, label %no
yes:
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
no:
  %e = call %Str @t2_str(i8* getelementptr ([1 x i8], [1 x i8]* @t2_empty, i64 0, i64 0), i64 0)
  %es = call %Slot @t2_box_str(%Str %e)
  ret %Slot %es
}
@t2_empty = private unnamed_addr constant [1 x i8] c"\00"
; t2_slot_int(x) / t2_slot_rand(x): perl's int and rand of a slot.
declare double @llvm.trunc.f64(double)
declare i32 @rand()
define internal %Slot @t2_slot_int(%Slot %s) {
  %d = call double @t2_slot_num(%Slot %s)
  %t = call double @llvm.trunc.f64(double %d)
  %r = call %Slot @t2_box_num(double %t)
  ret %Slot %r
}
define internal %Slot @t2_slot_rand(%Slot %s) {
  %x = call double @t2_slot_num(%Slot %s)
  %z = fcmp oeq double %x, 0.0
  %m = select i1 %z, double 1.0, double %x
  %r = call i32 @rand()
  %rd = sitofp i32 %r to double
  %u = fdiv double %rd, 2147483648.0
  %v = fmul double %u, %m
  %b = call %Slot @t2_box_num(double %v)
  ret %Slot %b
}
define internal %Slot @t2_box_num(double %v) {
  %i = bitcast double %v to i64
  %s = call %Slot @t2_slot(i8 2, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_box_str(%Str %v) {
  %m = call i8* @malloc(i64 16)
  %p = bitcast i8* %m to %Str*
  store %Str %v, %Str* %p
  %i = ptrtoint %Str* %p to i64
  %s = call %Slot @t2_slot(i8 3, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_env(i8* %k) {
entry:
  %v = call i8* @getenv(i8* %k)
  %none = icmp eq i8* %v, null
  br i1 %none, label %undef, label %set
undef:
  %u = call %Slot @t2_slot(i8 0, i64 0)
  ret %Slot %u
set:
  %n = call i64 @strlen(i8* %v)
  %s = call %Str @t2_str(i8* %v, i64 %n)
  %b = call %Slot @t2_box_str(%Str %s)
  ret %Slot %b
}
define internal %Slot @t2_box_bool(i1 %b) {
entry:
  br i1 %b, label %t, label %f
t:
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
f:
  %e = call %Str @t2_str(i8* null, i64 0)
  %no = call %Slot @t2_box_str(%Str %e)
  ret %Slot %no
}
declare void @exit(i32)
define internal double @t2_div(double %x, double %y, i8* %msg, i64 %n) {
entry:
  %z = fcmp oeq double %y, 0.0
  br i1 %z, label %die, label %ok
die:
  %m = call %Str @t2_str(i8* %msg, i64 %n)
  call void @t2_die_unwind(%Str %m)
  ret double 0.0
ok:
  %q = fdiv double %x, %y
  ret double %q
}
define internal i64 @t2_mod(i64 %x, i64 %y, i8* %msg, i64 %n) {
entry:
  %z = icmp eq i64 %y, 0
  br i1 %z, label %die, label %ok
die:
  %m = call %Str @t2_str(i8* %msg, i64 %n)
  call void @t2_die_unwind(%Str %m)
  ret i64 0
ok:
  %r = srem i64 %x, %y
  %rnz = icmp ne i64 %r, 0
  %rneg = icmp slt i64 %r, 0
  %yneg = icmp slt i64 %y, 0
  %diff = xor i1 %rneg, %yneg
  %fix = and i1 %rnz, %diff
  %r2 = add i64 %r, %y
  %res = select i1 %fix, i64 %r2, i64 %r
  ret i64 %res
}
; PERL'S ++ AND --. A string of letters then digits, starting with a letter,
; increments by magic ("az" -> "ba", "Zz" -> "AAa", "a9" -> "b0"); any other
; string, and -- always, go by its number -- an Int when it is a whole one.
define internal i1 @t2_is_magic(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %no, label %first
first:
  %c0 = load i8, i8* %p
  %l0 = call i1 @t2_is_letter(i8 %c0)
  ; (perl's /^[a-zA-Z]*[0-9]*$/: no letters at all is magic too -- "007"++ is "008")
  %g0 = icmp uge i8 %c0, 48
  %e0 = icmp ule i8 %c0, 57
  %d0 = and i1 %g0, %e0
  %ok0 = or i1 %l0, %d0
  br i1 %ok0, label %loop, label %no
loop:
  %i = phi i64 [ 1, %first ], [ %i1, %next ]
  %digits = phi i1 [ %d0, %first ], [ %d1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %yes
body:
  %cp = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %cp
  %isl = call i1 @t2_is_letter(i8 %c)
  %ge0 = icmp uge i8 %c, 48
  %le9 = icmp ule i8 %c, 57
  %isd = and i1 %ge0, %le9
  ; a letter after a digit ends the pattern
  %lad = and i1 %isl, %digits
  %neither = xor i1 %isl, true
  %notd = xor i1 %isd, true
  %bad0 = and i1 %neither, %notd
  %bad = or i1 %bad0, %lad
  br i1 %bad, label %no, label %next
next:
  %i1 = add i64 %i, 1
  %d1 = or i1 %digits, %isd
  br label %loop
yes:
  ret i1 1
no:
  ret i1 0
}
define internal i1 @t2_is_letter(i8 %c) {
  %lo1 = icmp uge i8 %c, 97
  %lo2 = icmp ule i8 %c, 122
  %lo = and i1 %lo1, %lo2
  %up1 = icmp uge i8 %c, 65
  %up2 = icmp ule i8 %c, 90
  %up = and i1 %up1, %up2
  %r = or i1 %lo, %up
  ret i1 %r
}
define internal %Str @t2_str_magic_inc(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 2
  %buf = call i8* @malloc(i64 %n1)
  %dst = getelementptr i8, i8* %buf, i64 1
  call i8* @memcpy(i8* %dst, i8* %p, i64 %n)
  %last = sub i64 %n, 1
  br label %loop
loop:
  %i = phi i64 [ %last, %entry ], [ %im1, %carry ]
  %cp = getelementptr i8, i8* %dst, i64 %i
  %c = load i8, i8* %cp
  %isz = icmp eq i8 %c, 122
  %isZ = icmp eq i8 %c, 90
  %is9 = icmp eq i8 %c, 57
  %wrap = or i1 %isz, %isZ
  %wrap2 = or i1 %wrap, %is9
  br i1 %wrap2, label %carry, label %bump
bump:
  %c1 = add i8 %c, 1
  store i8 %c1, i8* %cp
  %r = call %Str @t2_str(i8* %dst, i64 %n)
  ret %Str %r
carry:
  %low = select i1 %isz, i8 97, i8 48
  %w = select i1 %isZ, i8 65, i8 %low
  store i8 %w, i8* %cp
  %im1 = sub i64 %i, 1
  %done = icmp slt i64 %im1, 0
  br i1 %done, label %grow, label %loop
grow:
  ; carried off the front: a new first character of the first's kind
  %f = load i8, i8* %dst
  %fA = icmp eq i8 %f, 65
  %f0 = icmp eq i8 %f, 48
  %lead0 = select i1 %fA, i8 65, i8 97
  %lead = select i1 %f0, i8 49, i8 %lead0   ; (a digit's is 1: "99"++ is "100")
  store i8 %lead, i8* %buf
  %n2 = add i64 %n, 1
  %g = call %Str @t2_str(i8* %buf, i64 %n2)
  ret %Str %g
}
define internal %Slot @t2_num_slot(double %d) {
entry:
  %i = fptosi double %d to i64
  %back = sitofp i64 %i to double
  %whole = fcmp oeq double %back, %d
  %small = fcmp olt double %d, 0x43E0000000000000
  %big = fcmp ogt double %d, 0xC3E0000000000000
  %fits0 = and i1 %small, %big
  %fits = and i1 %whole, %fits0
  br i1 %fits, label %int, label %num
int:
  %si = call %Slot @t2_box_i64(i64 %i)
  ret %Slot %si
num:
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
define internal %Slot @t2_slot_step(%Slot %s, i64 %by, i1 %magic) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str ]
int:
  %v = extractvalue %Slot %s, 1
  %r = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v, i64 %by)
  %ov = extractvalue { i64, i1 } %r, 1
  br i1 %ov, label %num, label %intok
intok:
  %rv = extractvalue { i64, i1 } %r, 0
  %si = call %Slot @t2_box_i64(i64 %rv)
  ret %Slot %si
num:
  %d = call double @t2_slot_num(%Slot %s)
  %dby = sitofp i64 %by to double
  %dr = fadd double %d, %dby
  %sn = call %Slot @t2_box_num(double %dr)
  ret %Slot %sn
str:
  %pv = extractvalue %Slot %s, 1
  %pp = inttoptr i64 %pv to %Str*
  %sv = load %Str, %Str* %pp
  %ism = call i1 @t2_is_magic(%Str %sv)
  %domagic = and i1 %ism, %magic
  br i1 %domagic, label %magicinc, label %strnum
magicinc:
  %ms = call %Str @t2_str_magic_inc(%Str %sv)
  %mslot = call %Slot @t2_box_str(%Str %ms)
  ret %Slot %mslot
strnum:
  %sd = call double @t2_str_num(%Str %sv)
  %sby = sitofp i64 %by to double
  %sr = fadd double %sd, %sby
  %ss = call %Slot @t2_num_slot(double %sr)
  ret %Slot %ss
undef:
  %su = call %Slot @t2_box_i64(i64 %by)
  ret %Slot %su
}
define internal %Slot @t2_slot_inc(%Slot %s) {
  %r = call %Slot @t2_slot_step(%Slot %s, i64 1, i1 1)
  ret %Slot %r
}
define internal %Slot @t2_slot_dec(%Slot %s) {
  %r = call %Slot @t2_slot_step(%Slot %s, i64 -1, i1 0)
  ret %Slot %r
}
define internal i1 @t2_defined(%Slot %s) {
  %t = extractvalue %Slot %s, 0
  %d = icmp ne i8 %t, 0
  ret i1 %d
}
define internal double @t2_slot_num(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str
                               i8 5, label %ref
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
int:
  %di = sitofp i64 %v to double
  ret double %di
num:
  %dn = bitcast i64 %v to double
  ret double %dn
str:
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %ds = call double @t2_str_num(%Str %sv)
  ret double %ds
undef:
  ret double 0.0
ref:
  %da = sitofp i64 %v to double
  ret double %da
}
define internal i64 @t2_slot_i64(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %isint = icmp eq i8 %t, 1
  br i1 %isint, label %int, label %other
int:
  %v = extractvalue %Slot %s, 1
  ret i64 %v
other:
  %d = call double @t2_slot_num(%Slot %s)
  %i = fptosi double %d to i64
  ret i64 %i
}
; PERL'S ARITHMETIC ON TWO SCALARS: two Ints give an Int unless it overflows,
; anything else a Num.
declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)
define internal %Slot @t2_slot_add(%Slot %x, %Slot %y) {
entry:
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %ix = icmp eq i8 %tx, 1
  %iy = icmp eq i8 %ty, 1
  %both = and i1 %ix, %iy
  br i1 %both, label %ints, label %nums
ints:
  %vx = extractvalue %Slot %x, 1
  %vy = extractvalue %Slot %y, 1
  %r = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %vx, i64 %vy)
  %ov = extractvalue { i64, i1 } %r, 1
  br i1 %ov, label %nums, label %int
int:
  %v = extractvalue { i64, i1 } %r, 0
  %si = call %Slot @t2_box_i64(i64 %v)
  ret %Slot %si
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = fadd double %dx, %dy
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
define internal %Slot @t2_slot_sub(%Slot %x, %Slot %y) {
entry:
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %ix = icmp eq i8 %tx, 1
  %iy = icmp eq i8 %ty, 1
  %both = and i1 %ix, %iy
  br i1 %both, label %ints, label %nums
ints:
  %vx = extractvalue %Slot %x, 1
  %vy = extractvalue %Slot %y, 1
  %r = call { i64, i1 } @llvm.ssub.with.overflow.i64(i64 %vx, i64 %vy)
  %ov = extractvalue { i64, i1 } %r, 1
  br i1 %ov, label %nums, label %int
int:
  %v = extractvalue { i64, i1 } %r, 0
  %si = call %Slot @t2_box_i64(i64 %v)
  ret %Slot %si
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = fsub double %dx, %dy
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
; -x, perl's (pp_negate): a number 0 - x (so -0.0 is 0); a string that begins
; with a letter or _ gets a "-", one with a "+" (or a lone "-") its sign turned;
; "-" then a digit or "." is a number. "-" then anything else hangs on whether
; perl reads it as a number ("-inf" does, "-abc" does not): stopped, not guessed.
@lit_neg_stop = private unnamed_addr constant [50 x i8] c"unary minus of a \22-\22 string: stopped (chalk, T2)\0A\00"
define internal %Slot @t2_slot_neg(%Slot %x) {
entry:
  %t = extractvalue %Slot %x, 0
  %isstr = icmp eq i8 %t, 3
  br i1 %isstr, label %str, label %num
num:
  %z = call %Slot @t2_box_i64(i64 0)
  %r = call %Slot @t2_slot_sub(%Slot %z, %Slot %x)
  ret %Slot %r
str:
  %s = call %Str @t2_slot_str(%Slot %x)
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %num, label %first
first:
  %c = load i8, i8* %p
  %let = call i1 @t2_is_letter(i8 %c)
  %und = icmp eq i8 %c, 95
  %id = or i1 %let, %und
  br i1 %id, label %prefix, label %sign
prefix:
  %m = call %Str @t2_str(i8* getelementptr ([2 x i8], [2 x i8]* @lit_minus, i64 0, i64 0), i64 1)
  %j = call %Str @t2_concat(%Str %m, %Str %s)
  %jb = call %Slot @t2_box_str(%Str %j)
  ret %Slot %jb
sign:
  %plus = icmp eq i8 %c, 43
  br i1 %plus, label %flip, label %minus
minus:
  %ism = icmp eq i8 %c, 45
  br i1 %ism, label %after, label %num
after:
  %lone = icmp eq i64 %n, 1
  br i1 %lone, label %flip, label %next
next:
  %p1 = getelementptr i8, i8* %p, i64 1
  %c1 = load i8, i8* %p1
  %d0 = icmp uge i8 %c1, 48
  %d1 = icmp ule i8 %c1, 57
  %dig = and i1 %d0, %d1
  %dot = icmp eq i8 %c1, 46
  %numy = or i1 %dig, %dot
  br i1 %numy, label %num, label %stop
stop:
  call void @t2_stop(i8* getelementptr ([50 x i8], [50 x i8]* @lit_neg_stop, i64 0, i64 0), i64 49)
  unreachable
flip:
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %n1)
  %to = select i1 %plus, i8 45, i8 43
  store i8 %to, i8* %buf
  %f = call %Str @t2_str(i8* %buf, i64 %n)
  %fb = call %Slot @t2_box_str(%Str %f)
  ret %Slot %fb
}
@lit_minus = private unnamed_addr constant [2 x i8] c"-\00"
; ref \$x: "REF" when $x holds a reference (tags 5..9), else "SCALAR". (T2
; holds no glob, lvalue or vstring values, the other answers perl gives.)
@lit_kind_ref = private unnamed_addr constant [4 x i8] c"REF\00"
@lit_kind_scalar = private unnamed_addr constant [7 x i8] c"SCALAR\00"
define internal %Slot @t2_kind_of_ref(%Slot %x) {
  %t = extractvalue %Slot %x, 0
  %lo = icmp uge i8 %t, 5
  %hi = icmp ule i8 %t, 9
  %isref = and i1 %lo, %hi
  %rs = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_kind_ref, i64 0, i64 0), i64 3)
  %ss = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_kind_scalar, i64 0, i64 0), i64 6)
  %s = select i1 %isref, %Str %rs, %Str %ss
  %b = call %Slot @t2_box_str(%Str %s)
  ret %Slot %b
}
define internal %Slot @t2_slot_mul(%Slot %x, %Slot %y) {
entry:
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %ix = icmp eq i8 %tx, 1
  %iy = icmp eq i8 %ty, 1
  %both = and i1 %ix, %iy
  br i1 %both, label %ints, label %nums
ints:
  %vx = extractvalue %Slot %x, 1
  %vy = extractvalue %Slot %y, 1
  %r = call { i64, i1 } @llvm.smul.with.overflow.i64(i64 %vx, i64 %vy)
  %ov = extractvalue { i64, i1 } %r, 1
  br i1 %ov, label %nums, label %int
int:
  %v = extractvalue { i64, i1 } %r, 0
  %si = call %Slot @t2_box_i64(i64 %v)
  ret %Slot %si
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = fmul double %dx, %dy
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}

define internal %Str @t2_slot_str(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str
                               i8 5, label %ref
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
int:
  %si = call %Str @t2_i64_str(i64 %v)
  ret %Str %si
num:
  %dn = bitcast i64 %v to double
  %sn = call %Str @t2_num_str(double %dn)
  ret %Str %sn
str:
  %p = inttoptr i64 %v to %Str*
  %ss = load %Str, %Str* %p
  ret %Str %ss
undef:
  %e = call %Str @t2_str(i8* null, i64 0)
  ret %Str %e
ref:
  %rs = call %Str @t2_ref_str(%Slot %s)
  ret %Str %rs
}
@fmt_ref = private unnamed_addr constant [12 x i8] c"%.*s(0x%lx)\00"
@lit_eqhash = private unnamed_addr constant [6 x i8] c"=HASH\00"
; t2_ref_str(r) -> perl's string of a reference: HASH(0x...), ARRAY(0x...),
; or Class=HASH(0x...) for an object.
define internal %Str @t2_ref_str(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %addr = extractvalue %Slot %s, 1
  %kind = call %Str @t2_reftype(%Slot %s)
  %c = call %Slot @t2_class_of(%Slot %s)
  br label %h
h:
  %ct = extractvalue %Slot %c, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %fmt
obj:
  %cn = call %Str @t2_slot_str(%Slot %c)
  %rxn = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_regexp, i64 0, i64 0), i64 6)
  %rxc = call i64 @t2_strcmp(%Str %cn, %Str %rxn)
  %isrx = icmp eq i64 %rxc, 0
  br i1 %isrx, label %qr, label %obj2
qr:
  %pk = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_qrpat, i64 0, i64 0), i64 7)
  %pv = call %Slot @t2_hget(%Slot %s, %Str %pk)
  %ps = call %Str @t2_slot_str(%Slot %pv)
  ret %Str %ps
obj2:
  %eq = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_eqhash, i64 0, i64 0), i64 1)
  %bt = call %Str @t2_basetype(%Slot %s)
  %eh = call %Str @t2_concat(%Str %eq, %Str %bt)
  %ck = call %Str @t2_concat(%Str %kind, %Str %eh)
  br label %fmt
fmt:
  %pre = phi %Str [ %kind, %h ], [ %ck, %obj2 ]
  %pp = extractvalue %Str %pre, 0
  %pl = extractvalue %Str %pre, 1
  %pl32 = trunc i64 %pl to i32
  %cap = add i64 %pl, 32
  %buf = call i8* @malloc(i64 %cap)
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 %cap, i8* getelementptr ([12 x i8], [12 x i8]* @fmt_ref, i64 0, i64 0), i32 %pl32, i8* %pp, i64 %addr)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}

; %Array: { len, cap, elements } -- a `my @a`, its elements %Slot.
; (field 4: the class a bless gave it, undef until -- an array's or a hash's)
%Array = type { i64, i64, %Slot*, %Meta*, %Slot }
declare i8* @realloc(i8*, i64)
declare i8* @memmove(i8*, i8*, i64)
define internal %Array* @t2_new_array() {
  %m = call i8* @malloc(i64 48)
  %a = bitcast i8* %m to %Array*
  store %Array zeroinitializer, %Array* %a
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* @t2_meta_default, %Meta** %mp
  ret %Array* %a
}
define internal i64 @t2_alen_d(%Array* %a) {
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  %n = load i64, i64* %lp
  ret i64 %n
}
; t2_agrow(a, n): room for n elements, the new ones undef.
define internal void @t2_agrow(%Array* %a, i64 %n) {
entry:
  %cp = getelementptr %Array, %Array* %a, i32 0, i32 1
  %cap = load i64, i64* %cp
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %fits = icmp sle i64 %n, %cap
  br i1 %fits, label %fill, label %grow
grow:
  %c2 = mul i64 %cap, 2
  %big = icmp sgt i64 %c2, %n
  %c3 = select i1 %big, i64 %c2, i64 %n
  %c4 = add i64 %c3, 4
  %bytes = mul i64 %c4, 16
  %old = load %Slot*, %Slot** %ep
  %o8 = bitcast %Slot* %old to i8*
  %new8 = call i8* @realloc(i8* %o8, i64 %bytes)
  %new = bitcast i8* %new8 to %Slot*
  store %Slot* %new, %Slot** %ep
  store i64 %c4, i64* %cp
  br label %fill
fill:
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  %len = load i64, i64* %lp
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %i = phi i64 [ %len, %fill ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %p = getelementptr %Slot, %Slot* %els, i64 %i
  store %Slot { i8 0, i64 1 }, %Slot* %p   ; (absent: perl's hole)
  %i1 = add i64 %i, 1
  br label %loop
done:
  %longer = icmp sgt i64 %n, %len
  %nl = select i1 %longer, i64 %n, i64 %len
  store i64 %nl, i64* %lp
  ret void
}
define internal void @t2_apush_d(%Array* %a, %Slot %v) {
  %n = call i64 @t2_alen(%Array* %a)
  %n1 = add i64 %n, 1
  call void @t2_agrow(%Array* %a, i64 %n1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %n
  %vt = extractvalue %Slot %v, 0
  %vu = icmp eq i8 %vt, 0
  %vn = select i1 %vu, %Slot zeroinitializer, %Slot %v
  store %Slot %vn, %Slot* %p
  ret void
}
; t2_aunshift(a, v): v in front, every element one further on.
define internal void @t2_aunshift_d(%Array* %a, %Slot %v) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %n1 = add i64 %n, 1
  call void @t2_agrow(%Array* %a, i64 %n1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %from = getelementptr %Slot, %Slot* %els, i64 %im
  %e = load %Slot, %Slot* %from
  %to = getelementptr %Slot, %Slot* %els, i64 %i
  store %Slot %e, %Slot* %to
  br label %loop
done:
  %vt = extractvalue %Slot %v, 0
  %vu = icmp eq i8 %vt, 0
  %vn = select i1 %vu, %Slot zeroinitializer, %Slot %v
  store %Slot %vn, %Slot* %els
  ret void
}
define internal %Slot @t2_aget_d(%Array* %a, i64 %i) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fromend = add i64 %i, %n
  %j = select i1 %neg, i64 %fromend, i64 %i
  %lo = icmp slt i64 %j, 0
  %hi = icmp sge i64 %j, %n
  %out = or i1 %lo, %hi
  br i1 %out, label %undef, label %get
get:
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  %v = load %Slot, %Slot* %p
  %vt = extractvalue %Slot %v, 0
  %vu = icmp eq i8 %vt, 0
  %vr = select i1 %vu, %Slot zeroinitializer, %Slot %v   ; (an absent one is undef)
  ret %Slot %vr
undef:
  ret %Slot zeroinitializer
}
@lit_aset = private unnamed_addr constant [64 x i8] c"Modification of non-creatable array value attempted, subscript \00"
; HOLES: an element perl has not made (past a store beyond the end, or $#a
; grown) is ABSENT -- tag undef, payload 1. Every reader takes it for undef;
; aget and the stores make it a plain undef, so it never leaves its array.
; exists $a[i] of a plain array: in it, and not absent.
define internal i1 @t2_aexists_d(%Array* %a, i64 %i) {
entry:
  %n = call i64 @t2_alen_d(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fromend = add i64 %i, %n
  %j = select i1 %neg, i64 %fromend, i64 %i
  %lo = icmp slt i64 %j, 0
  %hi = icmp sge i64 %j, %n
  %out = or i1 %lo, %hi
  br i1 %out, label %no, label %look
look:
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  %v = load %Slot, %Slot* %p
  %t = extractvalue %Slot %v, 0
  %w = extractvalue %Slot %v, 1
  %ut = icmp eq i8 %t, 0
  %uw = icmp eq i64 %w, 1
  %absent = and i1 %ut, %uw
  %there = xor i1 %absent, true
  ret i1 %there
no:
  ret i1 false
}
; A TIED ARRAY'S are its class's EXISTS and STORESIZE (n + 1); a negative
; index counts back from its FETCHSIZE, as perl's does. Both are reached through
; the container's metaobject (slots 18 and 19).
@lit_tm_storesize = private unnamed_addr constant [10 x i8] c"STORESIZE\00"
define internal i1 @t2_tie_aexists(%Array* %a, i64 %i) {
entry:
  %neg = icmp slt i64 %i, 0
  br i1 %neg, label %back, label %ask
back:
  %n = call i64 @t2_tie_alen(%Array* %a)
  %fromend = add i64 %i, %n
  br label %ask
ask:
  %j = phi i64 [ %i, %entry ], [ %fromend, %back ]
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %js = call %Slot @t2_box_i64(i64 %j)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_apush(%Array* %args, %Slot %js)
  %m = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_exists, i64 0, i64 0), i64 6)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  %b = call i1 @t2_truth_slot(%Slot %r)
  ret i1 %b
}
define internal void @t2_tie_aset_len(%Array* %a, i64 %n) {
entry:
  %n1 = add i64 %n, 1
  %neg = icmp slt i64 %n1, 0
  %nl = select i1 %neg, i64 0, i64 %n1
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ns = call %Slot @t2_box_i64(i64 %nl)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_apush(%Array* %args, %Slot %ns)
  %m = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_tm_storesize, i64 0, i64 0), i64 9)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  ret void
}
define internal i1 @t2_aexists(%Array* %a, i64 %i) {
  %f = call i8* @t2_vt(%Array* %a, i64 18)
  %fn = bitcast i8* %f to i1 (%Array*, i64)*
  %r = call i1 %fn(%Array* %a, i64 %i)
  ret i1 %r
}
define internal void @t2_aset_len(%Array* %a, i64 %n) {
  %f = call i8* @t2_vt(%Array* %a, i64 19)
  %fn = bitcast i8* %f to void (%Array*, i64)*
  call void %fn(%Array* %a, i64 %n)
  ret void
}
; $#a = n: n + 1 elements (none below -1); grown, the new ones are absent.
define internal void @t2_aset_len_d(%Array* %a, i64 %n) {
entry:
  %n1 = add i64 %n, 1
  %neg = icmp slt i64 %n1, 0
  %nl = select i1 %neg, i64 0, i64 %n1
  %len = call i64 @t2_alen_d(%Array* %a)
  %shrink = icmp sle i64 %nl, %len
  br i1 %shrink, label %cut, label %grow
cut:
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 %nl, i64* %lp
  ret void
grow:
  call void @t2_agrow(%Array* %a, i64 %nl)
  ret void
}
define internal void @t2_aset_d(%Array* %a, i64 %i, %Slot %v, i8* %at, i64 %atn) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fromend = add i64 %i, %n
  %j = select i1 %neg, i64 %fromend, i64 %i
  %lo = icmp slt i64 %j, 0
  br i1 %lo, label %die, label %set
set:
  %j1 = add i64 %j, 1
  call void @t2_agrow(%Array* %a, i64 %j1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  %vt = extractvalue %Slot %v, 0
  %vu = icmp eq i8 %vt, 0
  %vn = select i1 %vu, %Slot zeroinitializer, %Slot %v
  store %Slot %vn, %Slot* %p
  ret void
die:
  %m = getelementptr [64 x i8], [64 x i8]* @lit_aset, i64 0, i64 0
  call i64 @write(i32 2, i8* %m, i64 63)
  %is = call %Str @t2_i64_str(i64 %i)
  %ip = extractvalue %Str %is, 0
  %in = extractvalue %Str %is, 1
  call i64 @write(i32 2, i8* %ip, i64 %in)
  call i64 @write(i32 2, i8* %at, i64 %atn)
  call void @t2_run_ends()
  call void @exit(i32 255)
  unreachable
}
define internal %Slot @t2_apop_d(%Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %undef, label %pop
pop:
  %n1 = sub i64 %n, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %n1)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 %n1, i64* %lp
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
define internal %Slot @t2_ashift_d(%Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %undef, label %shift
shift:
  %v = call %Slot @t2_aget(%Array* %a, i64 0)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %d = bitcast %Slot* %els to i8*
  %s1 = getelementptr %Slot, %Slot* %els, i64 1
  %s = bitcast %Slot* %s1 to i8*
  %n1 = sub i64 %n, 1
  %bytes = mul i64 %n1, 16
  call i8* @memmove(i8* %d, i8* %s, i64 %bytes)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 %n1, i64* %lp
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
define internal %Str @t2_join(%Str %sep, %Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %e = call %Str @t2_str(i8* null, i64 0)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %acc = phi %Str [ %e, %entry ], [ %acc2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %first = icmp eq i64 %i, 0
  %pre = call %Str @t2_concat(%Str %acc, %Str %sep)
  %acc1 = select i1 %first, %Str %acc, %Str %pre
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  %vs = call %Str @t2_slot_str(%Slot %v)
  %acc2 = call %Str @t2_concat(%Str %acc1, %Str %vs)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret %Str %acc
}
define internal i1 @t2_truth_i64(i64 %v) {
  %b = icmp ne i64 %v, 0
  ret i1 %b
}
define internal i1 @t2_truth_num(double %v) {
  %b = fcmp une double %v, 0.0
  ret i1 %b
}
define internal i1 @t2_truth_str(%Str %s) {
entry:
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %no, label %one
one:
  %is1 = icmp eq i64 %n, 1
  br i1 %is1, label %check, label %yes
check:
  %p = extractvalue %Str %s, 0
  %c = load i8, i8* %p
  %zero = icmp eq i8 %c, 48
  br i1 %zero, label %no, label %yes
yes:
  ret i1 1
no:
  ret i1 0
}
define internal i1 @t2_truth_slot(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str
                               i8 5, label %ref
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
int:
  %bi = icmp ne i64 %v, 0
  ret i1 %bi
num:
  %d = bitcast i64 %v to double
  %bn = fcmp une double %d, 0.0
  ret i1 %bn
str:
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %bs = call i1 @t2_truth_str(%Str %sv)
  ret i1 %bs
undef:
  ret i1 0
ref:
  ret i1 1
}
; A HASH REFERENCE is a %Slot of tag 5 whose payload is an %Array of its
; pairs, key (a boxed Str) then value, in insertion order (perl's own order
; is not promised; keys/each are not this slice's).
declare i32 @memcmp(i8*, i8*, i64)
@msg_notahash = private unnamed_addr constant [75 x i8] c"chalk: refused at run time: a hash element read through no HASH reference\0A\00"
@lit_hash = private unnamed_addr constant [5 x i8] c"HASH\00"
@lit_array = private unnamed_addr constant [6 x i8] c"ARRAY\00"
@lit_code = private unnamed_addr constant [5 x i8] c"CODE\00"
@lit_scalar = private unnamed_addr constant [7 x i8] c"SCALAR\00"
@msg_notanarray = private unnamed_addr constant [78 x i8] c"chalk: refused at run time: an array element read through no ARRAY reference\0A\00"
@msg_refstr = private unnamed_addr constant [62 x i8] c"chalk: refused at run time: a reference read as a str or num\0A\00"
define internal void @t2_stop(i8* %m, i64 %n) {
  %w = call i64 @write(i32 2, i8* %m, i64 %n)
  call void @t2_run_ends()
  call void @exit(i32 255)
  unreachable
}
define internal void @t2_refscalar() {
  call void @t2_stop(i8* getelementptr ([62 x i8], [62 x i8]* @msg_refstr, i64 0, i64 0), i64 61)
  unreachable
}
; A HASH'S %Array: element 0 is the class a bless gave it (undef until),
; then key, value pairs.
define internal %Slot @t2_hnew() {
  %a = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %a, %Slot zeroinitializer)
  %i = ptrtoint %Array* %a to i64
  %s = call %Slot @t2_slot(i8 5, i64 %i)
  ret %Slot %s
}
define internal %Array* @t2_harr(%Slot %h) {
entry:
  %t = extractvalue %Slot %h, 0
  %ok = icmp eq i8 %t, 5
  br i1 %ok, label %yes, label %no
no:
  call void @t2_stop(i8* getelementptr ([75 x i8], [75 x i8]* @msg_notahash, i64 0, i64 0), i64 74)
  unreachable
yes:
  %v = extractvalue %Slot %h, 1
  %a = inttoptr i64 %v to %Array*
  ret %Array* %a
}
; t2_hfind(a, k) -> the index of k's key slot, or -1.
define internal i64 @t2_hfind(%Array* %a, %Str %k) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %kp = extractvalue %Str %k, 0
  %kl = extractvalue %Str %k, 1
  br label %loop
loop:
  %i = phi i64 [ 1, %entry ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %none
body:
  %ks = call %Slot @t2_aget(%Array* %a, i64 %i)
  %kstr = call %Str @t2_slot_str(%Slot %ks)
  %ol = extractvalue %Str %kstr, 1
  %samelen = icmp eq i64 %ol, %kl
  br i1 %samelen, label %cmp, label %next
cmp:
  %op = extractvalue %Str %kstr, 0
  %c = call i32 @memcmp(i8* %op, i8* %kp, i64 %kl)
  %eq = icmp eq i32 %c, 0
  br i1 %eq, label %found, label %next
next:
  %i2 = add i64 %i, 2
  br label %loop
found:
  ret i64 %i
none:
  ret i64 -1
}
@msg_blessnot = private unnamed_addr constant [78 x i8] c"chalk: refused at run time: a bless of what is not a hash or array reference\0A\00"
define internal %Slot @t2_bless(%Slot %h, %Str %c) {
entry:
  %t = extractvalue %Slot %h, 0
  %ish = icmp eq i8 %t, 5
  %isa = icmp eq i8 %t, 6
  %ok = or i1 %ish, %isa
  br i1 %ok, label %set, label %other
other:
  %issc = icmp eq i8 %t, 9
  %iscd = icmp eq i8 %t, 8
  %side = or i1 %issc, %iscd
  br i1 %side, label %table, label %bad
table:
  %tb = call %Slot @t2_ghash(%Slot* @t2_blessings)
  %k = call %Str @t2_addr_key(%Slot %h)
  %tcs = call %Slot @t2_box_str(%Str %c)
  call void @t2_hset(%Slot %tb, %Str %k, %Slot %tcs)
  ret %Slot %h
bad:
  call void @t2_stop(i8* getelementptr ([78 x i8], [78 x i8]* @msg_blessnot, i64 0, i64 0), i64 77)
  unreachable
set:
  %cs = call %Slot @t2_box_str(%Str %c)
  %v = extractvalue %Slot %h, 1
  %a = inttoptr i64 %v to %Array*
  %cp = getelementptr %Array, %Array* %a, i32 0, i32 4
  store %Slot %cs, %Slot* %cp
  ret %Slot %h
}
; t2_class_of(s) -> the class a hash or array reference was blessed into
; (a boxed Str), else undef.
define internal %Slot @t2_class_of(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %ish = icmp eq i8 %t, 5
  %isa = icmp eq i8 %t, 6
  %ok = or i1 %ish, %isa
  br i1 %ok, label %agg, label %other
agg:
  %v = extractvalue %Slot %s, 1
  %a = inttoptr i64 %v to %Array*
  %cp = getelementptr %Array, %Array* %a, i32 0, i32 4
  %c = load %Slot, %Slot* %cp
  ret %Slot %c
other:
  %issc = icmp eq i8 %t, 9
  %iscd = icmp eq i8 %t, 8
  %side = or i1 %issc, %iscd
  br i1 %side, label %table, label %none
table:
  %tb = call %Slot @t2_ghash(%Slot* @t2_blessings)
  %k = call %Str @t2_addr_key(%Slot %s)
  %tc = call %Slot @t2_hget(%Slot %tb, %Str %k)
  ret %Slot %tc
none:
  ret %Slot zeroinitializer
}
; A SCALAR OR CODE REFERENCE'S CLASS: no header to hold it, so a table keyed
; by its address (t2_addr_key).
@t2_blessings = internal global %Slot zeroinitializer
define internal %Str @t2_addr_key(%Slot %s) {
  %a = extractvalue %Slot %s, 1
  %b = call %Slot @t2_box_i64(i64 %a)
  %k = call %Str @t2_slot_str(%Slot %b)
  ret %Str %k
}
; A SCALAR REFERENCE (`\$x`) is a %Slot of tag 9 whose payload is the
; variable's heap cell.
define internal %Slot @t2_sref(%Slot* %c) {
  %i = ptrtoint %Slot* %c to i64
  %s = call %Slot @t2_slot(i8 9, i64 %i)
  ret %Slot %s
}
@lit_sc_undef = private unnamed_addr constant [51 x i8] c"Can't use an undefined value as a SCALAR reference\00"
@lit_sc_not = private unnamed_addr constant [23 x i8] c"Not a SCALAR reference\00"
@lit_sc_str0 = private unnamed_addr constant [20 x i8] c"Can't use string (\22\00"
@lit_sc_str1 = private unnamed_addr constant [46 x i8] c"\22) as a SCALAR ref while \22strict refs\22 in use\00"
@lit_sc_more = private unnamed_addr constant [5 x i8] c"\22...\00"
@msg_symref = private unnamed_addr constant [65 x i8] c"chalk: refused at run time: a string as a reference (no strict)\0A\00"
; t2_sderef_cell(r, strict, at, n) -> the cell r refers to; null after
; perl's die (what r is named), a stop for a name without strict refs.
define internal %Slot* @t2_sderef_cell(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn) {
entry:
  %t = extractvalue %Slot %r, 0
  switch i8 %t, label %str [ i8 9, label %ok
                             i8 0, label %undef
                             i8 5, label %not
                             i8 6, label %not
                             i8 7, label %not
                             i8 8, label %not ]
ok:
  %v = extractvalue %Slot %r, 1
  %c = inttoptr i64 %v to %Slot*
  ret %Slot* %c
undef:
  br i1 %strict, label %undefdie, label %none
undefdie:
  %u = call %Str @t2_str(i8* getelementptr ([51 x i8], [51 x i8]* @lit_sc_undef, i64 0, i64 0), i64 50)
  br label %die
not:
  %nm = call %Str @t2_str(i8* getelementptr ([23 x i8], [23 x i8]* @lit_sc_not, i64 0, i64 0), i64 22)
  br label %die
str:
  br i1 %strict, label %strdie, label %sym
sym:
  %nm0 = call %Str @t2_slot_str(%Slot %r)
  %pks = call %Str @t2_str(i8* %pk, i64 %pkn)
  %cell = call %Slot* @t2_symref(%Str %nm0, %Str %pks)
  ret %Slot* %cell
strdie:
  %sv = call %Str @t2_slot_str(%Slot %r)
  %sl = extractvalue %Str %sv, 1
  %long = icmp ugt i64 %sl, 32
  %cut = select i1 %long, i64 32, i64 %sl
  %sp = extractvalue %Str %sv, 0
  %head = call %Str @t2_str(i8* %sp, i64 %cut)
  %p0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_sc_str0, i64 0, i64 0), i64 19)
  %p1 = call %Str @t2_concat(%Str %p0, %Str %head)
  %more = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_sc_more, i64 0, i64 0), i64 4)
  %p2 = call %Str @t2_concat(%Str %p1, %Str %more)
  %p1b = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_sc_str0, i64 0, i64 0), i64 0)
  %tail0 = call %Str @t2_str(i8* getelementptr ([46 x i8], [46 x i8]* @lit_sc_str1, i64 0, i64 0), i64 45)
  %tail1 = call %Str @t2_str(i8* getelementptr ([46 x i8], [46 x i8]* @lit_sc_str1, i64 0, i64 1), i64 44)
  %lp = select i1 %long, %Str %p2, %Str %p1
  %tl = select i1 %long, %Str %tail1, %Str %tail0
  %sm = call %Str @t2_concat(%Str %lp, %Str %tl)
  br label %die
die:
  %m0 = phi %Str [ %u, %undefdie ], [ %nm, %not ], [ %sm, %strdie ]
  %as = call %Str @t2_str(i8* %at, i64 %n)
  %m = call %Str @t2_concat(%Str %m0, %Str %as)
  call void @t2_die_unwind(%Str %m)
  ret %Slot* null
none:
  ret %Slot* null
}
; THE PROGRAM'S PACKAGE SCALARS BY NAME ("main::x" -> a SCALAR reference to its
; global), for a string used as a reference without strict refs; one no one
; named is made on first use, as perl's. t2_symtab_init (the printer's) fills it.
@t2_symtab = internal global %Slot zeroinitializer
@t2_symtab_ready = internal global i1 0
@lit_colons = private unnamed_addr constant [3 x i8] c"::\00"
@lit_mainpk = private unnamed_addr constant [5 x i8] c"main\00"
define internal void @t2_symtab_add(i8* %p, i64 %n, %Slot* %g) {
  %t = call %Slot @t2_ghash(%Slot* @t2_symtab)
  %k = call %Str @t2_str(i8* %p, i64 %n)
  %s = call %Slot @t2_sref(%Slot* %g)
  call void @t2_hset(%Slot %t, %Str %k, %Slot %s)
  ret void
}
; t2_has_colons(s) -> whether s holds "::"
define internal i1 @t2_has_colons(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %last = sub i64 %n, 1
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %next ]
  %more = icmp slt i64 %i, %last
  br i1 %more, label %look, label %no
look:
  %a = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %a
  %i2 = add i64 %i, 1
  %b = getelementptr i8, i8* %p, i64 %i2
  %d = load i8, i8* %b
  %c1 = icmp eq i8 %c, 58
  %d1 = icmp eq i8 %d, 58
  %both = and i1 %c1, %d1
  br i1 %both, label %yes, label %next
next:
  br label %loop
yes:
  ret i1 1
no:
  ret i1 0
}
define internal %Slot* @t2_symref(%Str %name, %Str %pk) {
entry:
  %ready = load i1, i1* @t2_symtab_ready
  br i1 %ready, label %go, label %init
init:
  store i1 1, i1* @t2_symtab_ready
  call void @t2_symtab_init()
  br label %go
go:
  %q = call i1 @t2_has_colons(%Str %name)
  br i1 %q, label %qual, label %unq
qual:
  %np = extractvalue %Str %name, 0
  %c0 = load i8, i8* %np
  %lead = icmp eq i8 %c0, 58
  br i1 %lead, label %lead_main, label %have
lead_main:
  %m = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_mainpk, i64 0, i64 0), i64 4)
  %ml = call %Str @t2_concat(%Str %m, %Str %name)
  br label %have
unq:
  %cc = call %Str @t2_str(i8* getelementptr ([3 x i8], [3 x i8]* @lit_colons, i64 0, i64 0), i64 2)
  %p1 = call %Str @t2_concat(%Str %pk, %Str %cc)
  %p2 = call %Str @t2_concat(%Str %p1, %Str %name)
  br label %have
have:
  %full = phi %Str [ %name, %qual ], [ %ml, %lead_main ], [ %p2, %unq ]
  %t = call %Slot @t2_ghash(%Slot* @t2_symtab)
  %s = call %Slot @t2_hget(%Slot %t, %Str %full)
  %st = extractvalue %Slot %s, 0
  %found = icmp eq i8 %st, 9
  br i1 %found, label %old, label %new
old:
  %v = extractvalue %Slot %s, 1
  %oc = inttoptr i64 %v to %Slot*
  ret %Slot* %oc
new:
  %mem = call i8* @malloc(i64 16)
  %nc = bitcast i8* %mem to %Slot*
  store %Slot zeroinitializer, %Slot* %nc
  %ns = call %Slot @t2_sref(%Slot* %nc)
  call void @t2_hset(%Slot %t, %Str %full, %Slot %ns)
  ret %Slot* %nc
}
define internal %Slot @t2_sderef(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn) {
  %c = call %Slot* @t2_sderef_cell(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn)
  %z = icmp eq %Slot* %c, null
  br i1 %z, label %undef, label %load
undef:
  ret %Slot zeroinitializer
load:
  %v = load %Slot, %Slot* %c
  ret %Slot %v
}
@msg_sstore_undef = private unnamed_addr constant [75 x i8] c"chalk: refused at run time: a store through an undefined scalar reference\0A\00"
define internal void @t2_sstore(%Slot %r, %Slot %v, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn) {
entry:
  %t = extractvalue %Slot %r, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %viv, label %go
viv:
  call void @t2_stop(i8* getelementptr ([75 x i8], [75 x i8]* @msg_sstore_undef, i64 0, i64 0), i64 74)
  unreachable
go:
  %c = call %Slot* @t2_sderef_cell(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn)
  %z = icmp eq %Slot* %c, null
  br i1 %z, label %done, label %st
st:
  store %Slot %v, %Slot* %c
  br label %done
done:
  ret void
}
; t2_reftype(s) -> perl's ref(): an object's class, HASH, or "" for no reference.
define internal %Str @t2_reftype(%Slot %s) {
entry:
  %c = call %Slot @t2_class_of(%Slot %s)
  %ct = extractvalue %Slot %c, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %plain
obj:
  %cn = call %Str @t2_slot_str(%Slot %c)
  ret %Str %cn
plain:
  %b = call %Str @t2_basetype(%Slot %s)
  ret %Str %b
}
; t2_basetype(s) -> what s refers to, blessed or not: HASH, ARRAY, CODE,
; SCALAR, or "" for no reference.
define internal %Str @t2_basetype(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %none [ i8 5, label %hash
                              i8 6, label %arr
                              i8 8, label %code
                              i8 9, label %sc ]
hash:
  %h = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_hash, i64 0, i64 0), i64 4)
  ret %Str %h
arr:
  %a = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_array, i64 0, i64 0), i64 5)
  ret %Str %a
code:
  %k = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_code, i64 0, i64 0), i64 4)
  ret %Str %k
sc:
  %q = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_scalar, i64 0, i64 0), i64 6)
  ret %Str %q
none:
  %e = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_hash, i64 0, i64 0), i64 0)
  ret %Str %e
}
@t2_stashes = internal global %Slot zeroinitializer
@lit_isa = private unnamed_addr constant [5 x i8] c"@ISA\00"
@lit_cm = private unnamed_addr constant [20 x i8] c"Can't call method \22\00"
@lit_undefv = private unnamed_addr constant [24 x i8] c"\22 on an undefined value\00"
@lit_unbl = private unnamed_addr constant [25 x i8] c"\22 on unblessed reference\00"
@lit_nopkg = private unnamed_addr constant [40 x i8] c"\22 without a package or object reference\00"
@lit_lom = private unnamed_addr constant [29 x i8] c"Can't locate object method \22\00"
@lit_via = private unnamed_addr constant [16 x i8] c"\22 via package \22\00"
@lit_q = private unnamed_addr constant [2 x i8] c"\22\00"
@lit_forgot = private unnamed_addr constant [32 x i8] c"\22 (perhaps you forgot to load \22\00"
@lit_qp = private unnamed_addr constant [4 x i8] c"\22?)\00"
@msg_arity = private unnamed_addr constant [68 x i8] c"chalk: refused at run time: a call of a signature of another arity\0A\00"
define internal %Slot @t2_stash_table() {
entry:
  %t = load %Slot, %Slot* @t2_stashes
  %tag = extractvalue %Slot %t, 0
  %made = icmp eq i8 %tag, 5
  br i1 %made, label %have, label %make
make:
  %n = call %Slot @t2_hnew()
  store %Slot %n, %Slot* @t2_stashes
  ret %Slot %n
have:
  ret %Slot %t
}
@t2_want = internal global i1 0   ; the caller's context: 1 a list
@t2_argc = internal global i32 0
@t2_argvp = internal global i8** null
@t2_ARGV = internal global %Array* null
define internal void @t2_save_args(i32 %c, i8** %v) {
  store i32 %c, i32* @t2_argc
  store i8** %v, i8*** @t2_argvp
  ; perl's $@ starts "" (defined)
  %e = call %Str @t2_str(i8* null, i64 0)
  %es = call %Slot @t2_box_str(%Str %e)
  store %Slot %es, %Slot* @t2_err
  ret void
}
; t2_argv() -> @ARGV: argv[1..] as strings, made once.
define internal %Array* @t2_argv() {
entry:
  %have = load %Array*, %Array** @t2_ARGV
  %made = icmp ne %Array* %have, null
  br i1 %made, label %done, label %make
make:
  %a = call %Array* @t2_new_array()
  %c32 = load i32, i32* @t2_argc
  %c = sext i32 %c32 to i64
  %v = load i8**, i8*** @t2_argvp
  br label %loop
loop:
  %i = phi i64 [ 1, %make ], [ %i2, %body ]
  %more = icmp slt i64 %i, %c
  br i1 %more, label %body, label %store
body:
  %pp = getelementptr i8*, i8** %v, i64 %i
  %p = load i8*, i8** %pp
  %n = call i64 @strlen(i8* %p)
  %s = call %Str @t2_str(i8* %p, i64 %n)
  %sl = call %Slot @t2_box_str(%Str %s)
  call void @t2_apush(%Array* %a, %Slot %sl)
  %i2 = add i64 %i, 1
  br label %loop
store:
  store %Array* %a, %Array** @t2_ARGV
  ret %Array* %a
done:
  ret %Array* %have
}
define internal %Slot @t2_aref(%Array* %a) {
  %i = ptrtoint %Array* %a to i64
  %s = call %Slot @t2_slot(i8 6, i64 %i)
  ret %Slot %s
}
; t2_aderef_r(s) -> for an element read through it: the array s refers to; an
; undef s reads as an empty one (perl's makes it), anything else stops.
define internal %Array* @t2_aderef_r(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %go
undef:
  %e = call %Array* @t2_new_array()
  ret %Array* %e
go:
  %a = call %Array* @t2_aderef(%Slot %s)
  ret %Array* %a
}
define internal %Array* @t2_aderef(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %ok = icmp eq i8 %t, 6
  br i1 %ok, label %yes, label %no
no:
  call void @t2_stop(i8* getelementptr ([78 x i8], [78 x i8]* @msg_notanarray, i64 0, i64 0), i64 77)
  unreachable
yes:
  %v = extractvalue %Slot %s, 1
  %a = inttoptr i64 %v to %Array*
  ret %Array* %a
}
@msg_oneof = private unnamed_addr constant [88 x i8] c"chalk: refused at run time: a list of other than one value passed as one argument (T2)\0A\00"
; t2_one_of(a) -> a's one element; a stop when it has another number.
define internal %Slot @t2_one_of(%Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %one = icmp eq i64 %n, 1
  br i1 %one, label %ok, label %bad
ok:
  %v = call %Slot @t2_aget(%Array* %a, i64 0)
  ret %Slot %v
bad:
  call void @t2_stop(i8* getelementptr ([88 x i8], [88 x i8]* @msg_oneof, i64 0, i64 0), i64 87)
  unreachable
}
; t2_list_of(v, want) -> in a list context a reference to a list of v; else v.
define internal %Slot @t2_list_of(%Slot %v, i1 %w) {
entry:
  br i1 %w, label %list, label %one
list:
  %a = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %a, %Slot %v)
  %r = call %Slot @t2_aref(%Array* %a)
  ret %Slot %r
one:
  ret %Slot %v
}
; CLOSURES: a captured variable's storage on the heap; a code value (tag 8)
; points at {its function, its cells}.
define internal %Slot* @t2_cell_new() {
  %m = call i8* @malloc(i64 16)
  %c = bitcast i8* %m to %Slot*
  store %Slot zeroinitializer, %Slot* %c
  ret %Slot* %c
}
define internal %Slot** @t2_env_new(i64 %n) {
  %b = mul i64 %n, 8
  %b1 = add i64 %b, 8
  %m = call i8* @malloc(i64 %b1)
  %e = bitcast i8* %m to %Slot**
  ret %Slot** %e
}
define internal void @t2_env_set(%Slot** %e, i64 %i, %Slot* %c) {
  %p = getelementptr %Slot*, %Slot** %e, i64 %i
  store %Slot* %c, %Slot** %p
  ret void
}
define internal %Slot* @t2_env_get(%Slot** %e, i64 %i) {
  %p = getelementptr %Slot*, %Slot** %e, i64 %i
  %c = load %Slot*, %Slot** %p
  ret %Slot* %c
}
define internal %Slot @t2_code_new(i8* %f, %Slot** %e) {
  %m = call i8* @malloc(i64 16)
  %pf = bitcast i8* %m to i8**
  store i8* %f, i8** %pf
  %pe0 = getelementptr i8*, i8** %pf, i64 1
  %pe = bitcast i8** %pe0 to %Slot***
  store %Slot** %e, %Slot*** %pe
  %i = ptrtoint i8* %m to i64
  %s = call %Slot @t2_slot(i8 8, i64 %i)
  ret %Slot %s
}
@msg_notcode = private unnamed_addr constant [69 x i8] c"chalk: refused at run time: a call of what is not a code value (T2)\0A\00"
define internal i8** @t2_code_of(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %ok = icmp eq i8 %t, 8
  br i1 %ok, label %yes, label %no
no:
  call void @t2_stop(i8* getelementptr ([69 x i8], [69 x i8]* @msg_notcode, i64 0, i64 0), i64 68)
  unreachable
yes:
  %v = extractvalue %Slot %s, 1
  %p = inttoptr i64 %v to i8**
  ret i8** %p
}
define internal i8* @t2_code_fn(%Slot %s) {
  %p = call i8** @t2_code_of(%Slot %s)
  %f = load i8*, i8** %p
  ret i8* %f
}
define internal %Slot** @t2_code_env(%Slot %s) {
  %p = call i8** @t2_code_of(%Slot %s)
  %pe0 = getelementptr i8*, i8** %p, i64 1
  %pe = bitcast i8** %pe0 to %Slot***
  %e = load %Slot**, %Slot*** %pe
  ret %Slot** %e
}
; t2_die(msg, at): perl's uncaught die -- the message to STDERR, `at` (" at
; FILE line N.\n") after it unless it ends in a newline; exit 255.
@lit_died = private unnamed_addr constant [5 x i8] c"Died\00"
define internal %Str @t2_die_msg(%Str %m, %Str %at) {
entry:
  %n = extractvalue %Str %m, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %died, label %last
died:
  ; die "" is "Died at FILE line N."
  %dm = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_died, i64 0, i64 0), i64 4)
  %dr = call %Str @t2_concat(%Str %dm, %Str %at)
  ret %Str %dr
last:
  %p = extractvalue %Str %m, 0
  %li = sub i64 %n, 1
  %lp = getelementptr i8, i8* %p, i64 %li
  %lc = load i8, i8* %lp
  %nl = icmp eq i8 %lc, 10
  br i1 %nl, label %done, label %addat
addat:
  %r = call %Str @t2_concat(%Str %m, %Str %at)
  ret %Str %r
done:
  ret %Str %m
}
define internal void @t2_die(%Str %m) {
  %p = extractvalue %Str %m, 0
  %n = extractvalue %Str %m, 1
  call i64 @write(i32 2, i8* %p, i64 %n)
  call void @t2_run_ends()
  call void @exit(i32 255)
  unreachable
}
; EVAL: $@ (@t2_err), the evals open at run time, and the dying flag a die
; in a sub sets for its callers to unwind by.
@t2_err = internal global %Slot zeroinitializer
@t2_eval_depth = internal global i64 0
@t2_dying = internal global i1 0
define internal void @t2_set_err(%Str %m) {
  %s = call %Slot @t2_box_str(%Str %m)
  store %Slot %s, %Slot* @t2_err
  ret void
}
define internal void @t2_eval_enter() {
  %d = load i64, i64* @t2_eval_depth
  %d1 = add i64 %d, 1
  store i64 %d1, i64* @t2_eval_depth
  ret void
}
define internal void @t2_eval_leave() {
  %d = load i64, i64* @t2_eval_depth
  %d1 = sub i64 %d, 1
  store i64 %d1, i64* @t2_eval_depth
  ret void
}
define internal void @t2_die_unwind(%Str %m) {
entry:
  %d = load i64, i64* @t2_eval_depth
  %open = icmp sgt i64 %d, 0
  br i1 %open, label %catch, label %exit
catch:
  call void @t2_set_err(%Str %m)
  store i1 1, i1* @t2_dying
  ret void
exit:
  call void @t2_die(%Str %m)
  unreachable
}
define internal void @t2_apush_if(%Array* %a, %Slot %v, i1 %c) {
entry:
  br i1 %c, label %push, label %done
push:
  call void @t2_apush(%Array* %a, %Slot %v)
  br label %done
done:
  ret void
}
define internal void @t2_aappend_d(%Array* %d, %Array* %s) {
entry:
  %n = call i64 @t2_alen(%Array* %s)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %s, i64 %i)
  call void @t2_apush(%Array* %d, %Slot %v)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret void
}
; t2_slot_length(s) -> perl's length of a scalar: undef for undef.
define internal %Slot @t2_slot_length(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %len
undef:
  ret %Slot zeroinitializer
len:
  %str = call %Str @t2_slot_str(%Slot %s)
  %n = extractvalue %Str %str, 1
  %r = call %Slot @t2_box_i64(i64 %n)
  ret %Slot %r
}
@msg_caseascii = private unnamed_addr constant [71 x i8] c"chalk: refused at run time: a case change of a string past ASCII (T2)\0A\00"
; t2_strcase(s, mode) -> s in ASCII case: 0 uc, 1 lc, 2 ucfirst, 3 lcfirst.
define internal %Str @t2_strcase(%Str %s, i64 %mode) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %cap = add i64 %n, 1
  %buf = call i8* @malloc(i64 %cap)
  %up = icmp eq i64 %mode, 0
  %up1 = icmp eq i64 %mode, 2
  %toup = or i1 %up, %up1
  %first = icmp sge i64 %mode, 2
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %put ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %sp = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %sp
  ; A BYTE PAST ASCII: perl's case of it depends on how it was read -- a stop.
  %high = icmp slt i8 %c, 0
  br i1 %high, label %past, label %ascii
past:
  call void @t2_stop(i8* getelementptr ([71 x i8], [71 x i8]* @msg_caseascii, i64 0, i64 0), i64 70)
  unreachable
ascii:
  %notfirst = icmp ne i64 %i, 0
  %keep = and i1 %first, %notfirst
  br i1 %keep, label %put0, label %conv
conv:
  br i1 %toup, label %upper, label %lower
upper:
  %isl = icmp uge i8 %c, 97
  %isl2 = icmp ule i8 %c, 122
  %lw = and i1 %isl, %isl2
  %cu = sub i8 %c, 32
  %ru = select i1 %lw, i8 %cu, i8 %c
  br label %put
lower:
  %isu = icmp uge i8 %c, 65
  %isu2 = icmp ule i8 %c, 90
  %uw = and i1 %isu, %isu2
  %cl = add i8 %c, 32
  %rl = select i1 %uw, i8 %cl, i8 %c
  br label %put
put0:
  br label %put
put:
  %r = phi i8 [ %ru, %upper ], [ %rl, %lower ], [ %c, %put0 ]
  %dp = getelementptr i8, i8* %buf, i64 %i
  store i8 %r, i8* %dp
  %i2 = add i64 %i, 1
  br label %loop
done:
  %out = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %out
}
; t2_strcmp(x, y) -> perl's cmp: -1, 0 or 1, bytewise, a prefix first.
define internal i64 @t2_strcmp(%Str %x, %Str %y) {
entry:
  %xp = extractvalue %Str %x, 0
  %xl = extractvalue %Str %x, 1
  %yp = extractvalue %Str %y, 0
  %yl = extractvalue %Str %y, 1
  %short = icmp slt i64 %xl, %yl
  %m = select i1 %short, i64 %xl, i64 %yl
  %r = call i32 @memcmp(i8* %xp, i8* %yp, i64 %m)
  %neg = icmp slt i32 %r, 0
  %pos = icmp sgt i32 %r, 0
  br i1 %neg, label %lt, label %notlt
notlt:
  br i1 %pos, label %gt, label %bylen
bylen:
  br i1 %short, label %lt, label %notshort
notshort:
  %longer = icmp sgt i64 %xl, %yl
  br i1 %longer, label %gt, label %eq
lt:
  ret i64 -1
gt:
  ret i64 1
eq:
  ret i64 0
}
; t2_stash(c) -> c's stash, made empty if c has none yet.
define internal %Slot @t2_stash(%Str %c) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %has = icmp eq i8 %st, 5
  br i1 %has, label %ok, label %make
make:
  %n = call %Slot @t2_hnew()
  call void @t2_hset(%Slot %t, %Str %c, %Slot %n)
  ret %Slot %n
ok:
  ret %Slot %s
}
; t2_mop_isa_arr(class) -> class's @ISA, the array lookup walks; made empty
; (and stored) when the class has none yet.
define internal %Array* @t2_mop_isa_arr(%Str %c) {
entry:
  %s = call %Slot @t2_stash(%Str %c)
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %it = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %it, 6
  br i1 %has, label %ok, label %make
ok:
  %iv = extractvalue %Slot %isa, 1
  %a = inttoptr i64 %iv to %Array*
  ret %Array* %a
make:
  %n = call %Array* @t2_new_array()
  call void @t2_mop_isa_set(%Str %c, %Array* %n)
  ret %Array* %n
}
define internal void @t2_mop_isa_set(%Str %c, %Array* %a) {
  %s = call %Slot @t2_stash(%Str %c)
  %k = call %Str @t2_isa_key()
  %ai = ptrtoint %Array* %a to i64
  %as = call %Slot @t2_slot(i8 6, i64 %ai)
  call void @t2_hset(%Slot %s, %Str %k, %Slot %as)
  ret void
}
define internal void @t2_mop_class(%Str %c) {
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hnew()
  call void @t2_hset(%Slot %t, %Str %c, %Slot %s)
  ret void
}
define internal %Str @t2_isa_key() {
  %k = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_isa, i64 0, i64 0), i64 4)
  ret %Str %k
}
; t2_mop_isa(class, parent): push parent onto class's @ISA.
define internal void @t2_mop_isa(%Str %c, %Str %p) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %tag = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %tag, 6
  br i1 %has, label %push, label %make
make:
  %na = call %Array* @t2_new_array()
  %ni = ptrtoint %Array* %na to i64
  %ns = call %Slot @t2_slot(i8 6, i64 %ni)
  call void @t2_hset(%Slot %s, %Str %k, %Slot %ns)
  br label %push
push:
  %cur = phi %Slot [ %isa, %entry ], [ %ns, %make ]
  %cv = extractvalue %Slot %cur, 1
  %arr = inttoptr i64 %cv to %Array*
  %ps = call %Slot @t2_box_str(%Str %p)
  call void @t2_apush(%Array* %arr, %Slot %ps)
  ret void
}
define internal void @t2_mop_def(%Str %c, %Str %m, i8* %f) {
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %fi = ptrtoint i8* %f to i64
  %fs = call %Slot @t2_slot(i8 7, i64 %fi)
  call void @t2_hset(%Slot %s, %Str %m, %Slot %fs)
  ret void
}
; t2_mfind1(class, m, skip) -> m's code in class (unless skip) or, depth first,
; its @ISA; null.
define internal i8* @t2_mfind1(%Str %c, %Str %m, i1 %skip) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %own, label %none
own:
  br i1 %skip, label %parents, label %look
look:
  %f = call %Slot @t2_hget(%Slot %s, %Str %m)
  %ft = extractvalue %Slot %f, 0
  %code = icmp eq i8 %ft, 7
  br i1 %code, label %found, label %parents
found:
  %fv = extractvalue %Slot %f, 1
  %fp = inttoptr i64 %fv to i8*
  ret i8* %fp
parents:
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %it = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %it, 6
  br i1 %has, label %walk, label %none
walk:
  %iv = extractvalue %Slot %isa, 1
  %arr = inttoptr i64 %iv to %Array*
  %n = call i64 @t2_alen(%Array* %arr)
  br label %loop
loop:
  %i = phi i64 [ 0, %walk ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %none
body:
  %ps = call %Slot @t2_aget(%Array* %arr, i64 %i)
  %pn = call %Str @t2_slot_str(%Slot %ps)
  %r = call i8* @t2_mfind1(%Str %pn, %Str %m, i1 0)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ret, label %next
ret:
  ret i8* %r
next:
  %i2 = add i64 %i, 1
  br label %loop
none:
  ret i8* null
}
; UNIVERSAL: perl's stash at the root of every method lookup, holding isa,
; can, DOES and VERSION. t2_universal_setup makes it.
@lit_universal = private unnamed_addr constant [10 x i8] c"UNIVERSAL\00"
@lit_u_isa = private unnamed_addr constant [4 x i8] c"isa\00"
@lit_u_can = private unnamed_addr constant [4 x i8] c"can\00"
@lit_u_does = private unnamed_addr constant [5 x i8] c"DOES\00"
define internal %Str @t2_universal_key() {
  %k = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_universal, i64 0, i64 0), i64 9)
  ret %Str %k
}
define internal void @t2_universal_setup() {
  %u = call %Str @t2_universal_key()
  call void @t2_mop_class(%Str %u)
  %i = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_u_isa, i64 0, i64 0), i64 3)
  call void @t2_mop_def(%Str %u, %Str %i, i8* bitcast (%Slot (%Array*)* @t2_u_isa_w to i8*))
  %c = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_u_can, i64 0, i64 0), i64 3)
  call void @t2_mop_def(%Str %u, %Str %c, i8* bitcast (%Slot (%Array*)* @t2_u_can_w to i8*))
  %d = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_u_does, i64 0, i64 0), i64 4)
  call void @t2_mop_def(%Str %u, %Str %d, i8* bitcast (%Slot (%Array*)* @t2_u_isa_w to i8*))
  %v = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_vname, i64 0, i64 0), i64 7)
  call void @t2_mop_def(%Str %u, %Str %v, i8* bitcast (%Slot (%Array*)* @t2_u_version_w to i8*))
  ret void
}
; t2_mfind_u(class, m, skip) -> as t2_mfind1, and failing that UNIVERSAL's.
define internal i8* @t2_mfind_u(%Str %c, %Str %m, i1 %skip) {
entry:
  %r = call i8* @t2_mfind1(%Str %c, %Str %m, i1 %skip)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ok, label %root
ok:
  ret i8* %r
root:
  %u = call %Str @t2_universal_key()
  %ru = call i8* @t2_mfind1(%Str %u, %Str %m, i1 0)
  ret i8* %ru
}
; t2_inv_class(inv) -> an object's class, or a class name (t2_mresolve checked it).
define internal %Str @t2_inv_class(%Slot %inv) {
entry:
  %t = extractvalue %Slot %inv, 0
  %ish = icmp eq i8 %t, 5
  %isa = icmp eq i8 %t, 6
  %isref = or i1 %ish, %isa
  br i1 %isref, label %ref, label %name
ref:
  %cl = call %Slot @t2_class_of(%Slot %inv)
  %cn = call %Str @t2_slot_str(%Slot %cl)
  ret %Str %cn
name:
  %nn = call %Str @t2_slot_str(%Slot %inv)
  ret %Str %nn
}
; t2_isa_walk(class, target) -> class is target or, depth first, inherits it.
define internal i1 @t2_isa_walk(%Str %c, %Str %target) {
entry:
  %d = call i64 @t2_strcmp(%Str %c, %Str %target)
  %same = icmp eq i64 %d, 0
  br i1 %same, label %yes, label %stash
stash:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %parents, label %no
parents:
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %it = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %it, 6
  br i1 %has, label %walk, label %no
walk:
  %iv = extractvalue %Slot %isa, 1
  %arr = inttoptr i64 %iv to %Array*
  %n = call i64 @t2_alen(%Array* %arr)
  br label %loop
loop:
  %i = phi i64 [ 0, %walk ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %no
body:
  %ps = call %Slot @t2_aget(%Array* %arr, i64 %i)
  %pn = call %Str @t2_slot_str(%Slot %ps)
  %r = call i1 @t2_isa_walk(%Str %pn, %Str %target)
  br i1 %r, label %yes, label %next
next:
  %i2 = add i64 %i, 1
  br label %loop
yes:
  ret i1 1
no:
  ret i1 0
}
; t2_bool(b) -> perl's true (1) or false (the empty string).
define internal %Slot @t2_bool(i1 %b) {
entry:
  br i1 %b, label %t, label %f
t:
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
f:
  %e = call %Str @t2_str(i8* null, i64 0)
  %no = call %Slot @t2_box_str(%Str %e)
  ret %Slot %no
}
; UNIVERSAL::isa (and DOES): method isa ($other) { $self isa $other }
define internal %Slot @t2_u_isa_w(%Array* %args) {
entry:
  %w = load i1, i1* @t2_want
  %inv = call %Slot @t2_aget(%Array* %args, i64 0)
  %o = call %Slot @t2_aget(%Array* %args, i64 1)
  %c = call %Str @t2_inv_class(%Slot %inv)
  %os = call %Str @t2_slot_str(%Slot %o)
  %b = call i1 @t2_isa_walk(%Str %c, %Str %os)
  %r = call %Slot @t2_bool(i1 %b)
  %rn = call %Slot @t2_list_of(%Slot %r, i1 %w)
  ret %Slot %rn
}
; t2_qr_match(re, subject) -> what a qr value's matcher gives: [start, end,
; groups...] or undef. A value of no class Regexp is a pattern built at run
; time: there is no graph of it -- stopped.
@lit_regexp = private unnamed_addr constant [7 x i8] c"Regexp\00"
@lit_matcher = private unnamed_addr constant [8 x i8] c"matcher\00"
@lit_qrpat = private unnamed_addr constant [8 x i8] c"pattern\00"
@msg_qr_runtime = private unnamed_addr constant [63 x i8] c"chalk: refused at run time: a regex pattern built at run time\0A\00"
define internal %Slot @t2_qr_match(%Slot %re, %Slot %subj) {
entry:
  %c = call %Slot @t2_class_of(%Slot %re)
  %cs = call %Str @t2_slot_str(%Slot %c)
  %rx = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_regexp, i64 0, i64 0), i64 6)
  %cmp = call i64 @t2_strcmp(%Str %cs, %Str %rx)
  %is = icmp eq i64 %cmp, 0
  br i1 %is, label %call, label %stop
stop:
  call void @t2_stop(i8* getelementptr ([63 x i8], [63 x i8]* @msg_qr_runtime, i64 0, i64 0), i64 62)
  unreachable
call:
  %mk = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_matcher, i64 0, i64 0), i64 7)
  %code = call %Slot @t2_hget(%Slot %re, %Str %mk)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %subj)
  store i1 0, i1* @t2_want
  %e = call %Slot** @t2_code_env(%Slot %code)
  %p = call i8* @t2_code_fn(%Slot %code)
  %f = bitcast i8* %p to %Slot (%Array*, %Slot**)*
  %r = call %Slot %f(%Array* %args, %Slot** %e)
  ret %Slot %r
}
; t2_pos_update(r, pos, z, keep): after an m//g -- matched ([start, end, ..]):
; pos is end, z end where the match was empty (else none); failed: both reset,
; unless /c (keep).
define internal void @t2_pos_update(%Slot %r, %Slot* %pc, %Slot* %zc, i1 %keep) {
entry:
  %t = extractvalue %Slot %r, 0
  %ok = icmp ne i8 %t, 0
  br i1 %ok, label %hit, label %miss
hit:
  %a = call %Array* @t2_aderef(%Slot %r)
  %s = call %Slot @t2_aget(%Array* %a, i64 0)
  %e = call %Slot @t2_aget(%Array* %a, i64 1)
  store %Slot %e, %Slot* %pc
  %si = extractvalue %Slot %s, 1
  %ei = extractvalue %Slot %e, 1
  %emp = icmp eq i64 %si, %ei
  %zz = select i1 %emp, %Slot %e, %Slot zeroinitializer
  store %Slot %zz, %Slot* %zc
  ret void
miss:
  br i1 %keep, label %done, label %reset
reset:
  store %Slot zeroinitializer, %Slot* %pc
  store %Slot zeroinitializer, %Slot* %zc
  br label %done
done:
  ret void
}
; t2_stash_tramp(args, env): a stash method called as a code value -- its
; code rides in env.
define internal %Slot @t2_stash_tramp(%Array* %args, %Slot** %env) {
entry:
  %f = bitcast %Slot** %env to %Slot (%Array*)*
  %r = call %Slot %f(%Array* %args)
  ret %Slot %r
}
; t2_unloaded_w: an unloaded sub's stash entry (can() finds it by name). Never
; called: a program that may call what can() hands back is refused.
define internal %Slot @t2_unloaded_w(%Array* %args) {
entry:
  unreachable
}
; UNIVERSAL::can: the method as a code value, or undef. (A list context gets a
; list, as a sub's wrapper gives: "[", A->can("x"), "]" read past its end.)
define internal %Slot @t2_u_can_w(%Array* %args) {
entry:
  %w = load i1, i1* @t2_want
  %inv = call %Slot @t2_aget(%Array* %args, i64 0)
  %m = call %Slot @t2_aget(%Array* %args, i64 1)
  %c = call %Str @t2_inv_class(%Slot %inv)
  %ms = call %Str @t2_slot_str(%Slot %m)
  %fp = call i8* @t2_mfind_u(%Str %c, %Str %ms, i1 0)
  %none = icmp eq i8* %fp, null
  br i1 %none, label %undef, label %code
undef:
  %un = call %Slot @t2_list_of(%Slot zeroinitializer, i1 %w)
  ret %Slot %un
code:
  %e = bitcast i8* %fp to %Slot**
  %cv = call %Slot @t2_code_new(i8* bitcast (%Slot (%Array*, %Slot**)* @t2_stash_tramp to i8*), %Slot** %e)
  %cn = call %Slot @t2_list_of(%Slot %cv, i1 %w)
  ret %Slot %cn
}
@lit_vkey = private unnamed_addr constant [9 x i8] c"$VERSION\00"
@lit_vname = private unnamed_addr constant [8 x i8] c"VERSION\00"
@lit_vver = private unnamed_addr constant [10 x i8] c" version \00"
@lit_vreq = private unnamed_addr constant [33 x i8] c" required--this is only version \00"
@lit_vnodef = private unnamed_addr constant [19 x i8] c" does not define $\00"
@lit_vnodef2 = private unnamed_addr constant [32 x i8] c"::VERSION--version check failed\00"
@lit_vneither = private unnamed_addr constant [59 x i8] c" defines neither package nor VERSION--version check failed\00"
; the call site t2_mresolve last saw (" at FILE line N.\n"): a UNIVERSAL method's die names it
@t2_call_at = internal global %Str zeroinitializer
; t2_mop_var(class, global): class's $VERSION is that global (VERSION reads it by the class's name).
define internal void @t2_mop_var(%Str %c, %Slot* %g) {
  %s = call %Slot @t2_stash(%Str %c)
  %k = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_vkey, i64 0, i64 0), i64 8)
  %gi = ptrtoint %Slot* %g to i64
  %gs = call %Slot @t2_slot(i8 1, i64 %gi)
  call void @t2_hset(%Slot %s, %Str %k, %Slot %gs)
  ret void
}
; t2_vnum(version) -> perl's number for it: decimal ("1.10" is 1.1), or dotted
; ("1.2.3", "v1.2": each part a thousandth of the one before).
define internal double @t2_vnum(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %some = icmp sgt i64 %n, 0
  br i1 %some, label %first, label %decimal
first:
  %c0 = load i8, i8* %p
  %isv = icmp eq i8 %c0, 118
  br i1 %isv, label %dotted, label %count
count:
  %ci = phi i64 [ 0, %first ], [ %ci2, %cstep ]
  %dots = phi i64 [ 0, %first ], [ %dots2, %cstep ]
  %cmore = icmp slt i64 %ci, %n
  br i1 %cmore, label %cstep, label %counted
cstep:
  %cp = getelementptr i8, i8* %p, i64 %ci
  %cc = load i8, i8* %cp
  %isdot = icmp eq i8 %cc, 46
  %inc = zext i1 %isdot to i64
  %dots2 = add i64 %dots, %inc
  %ci2 = add i64 %ci, 1
  br label %count
counted:
  %many = icmp sgt i64 %dots, 1
  br i1 %many, label %dotted, label %decimal
decimal:
  %sl = call %Slot @t2_box_str(%Str %s)
  %d = call double @t2_slot_num(%Slot %sl)
  ret double %d
dotted:
  %st0 = load i8, i8* %p
  %lead = icmp eq i8 %st0, 118
  %i0 = zext i1 %lead to i64
  br label %loop
loop:
  %i = phi i64 [ %i0, %dotted ], [ %inext, %digit ], [ %inext, %dot ]
  %part = phi i64 [ 0, %dotted ], [ %part2, %digit ], [ 0, %dot ]
  %acc = phi double [ 0.0, %dotted ], [ %acc, %digit ], [ %acc2, %dot ]
  %scale = phi double [ 1.0, %dotted ], [ %scale, %digit ], [ %scale2, %dot ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %ch, label %end
ch:
  %chp = getelementptr i8, i8* %p, i64 %i
  %chv = load i8, i8* %chp
  %inext = add i64 %i, 1
  %isd = icmp eq i8 %chv, 46
  br i1 %isd, label %dot, label %digit
dot:
  %pf = sitofp i64 %part to double
  %add = fmul double %pf, %scale
  %acc2 = fadd double %acc, %add
  %scale2 = fdiv double %scale, 1000.0
  br label %loop
digit:
  %dv = zext i8 %chv to i64
  %dd = sub i64 %dv, 48
  %p10 = mul i64 %part, 10
  %part2 = add i64 %p10, %dd
  br label %loop
end:
  %pf2 = sitofp i64 %part to double
  %add2 = fmul double %pf2, %scale
  %r = fadd double %acc, %add2
  ret double %r
}
; UNIVERSAL::VERSION: the class's own $VERSION; with a wanted version,
; perl's check, dying as perl does where it fails.
define internal %Slot @t2_u_version_w(%Array* %args) {
entry:
  %w = load i1, i1* @t2_want
  %inv = call %Slot @t2_aget(%Array* %args, i64 0)
  %c = call %Str @t2_inv_class(%Slot %inv)
  %tb = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %tb, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %look, label %check
look:
  %k = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_vkey, i64 0, i64 0), i64 8)
  %g = call %Slot @t2_hget(%Slot %s, %Str %k)
  %gt = extractvalue %Slot %g, 0
  %hasv = icmp eq i8 %gt, 1
  br i1 %hasv, label %load, label %check
load:
  %gi = extractvalue %Slot %g, 1
  %gp = inttoptr i64 %gi to %Slot*
  %vl = load %Slot, %Slot* %gp
  %vt = extractvalue %Slot %vl, 0
  %vdef = icmp ne i8 %vt, 0
  %vk = select i1 %vdef, i8 2, i8 1
  br label %check
check:
  %v = phi %Slot [ zeroinitializer, %entry ], [ zeroinitializer, %look ], [ %vl, %load ]
  %kind = phi i8 [ 0, %entry ], [ 1, %look ], [ %vk, %load ]
  %na = call i64 @t2_alen(%Array* %args)
  %req = icmp sgt i64 %na, 1
  br i1 %req, label %need, label %give
give:
  %rn = call %Slot @t2_list_of(%Slot %v, i1 %w)
  ret %Slot %rn
need:
  %want = call %Slot @t2_aget(%Array* %args, i64 1)
  %rs = call %Str @t2_slot_str(%Slot %want)
  switch i8 %kind, label %cmp [ i8 0, label %neither i8 1, label %nodef ]
cmp:
  %vs = call %Str @t2_slot_str(%Slot %v)
  %vn = call double @t2_vnum(%Str %vs)
  %wn = call double @t2_vnum(%Str %rs)
  %ok = fcmp oge double %vn, %wn
  br i1 %ok, label %give, label %low
low:
  %l0 = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_vver, i64 0, i64 0), i64 9)
  %l1 = call %Str @t2_concat(%Str %c, %Str %l0)
  %l2 = call %Str @t2_concat(%Str %l1, %Str %rs)
  %l3 = call %Str @t2_str(i8* getelementptr ([33 x i8], [33 x i8]* @lit_vreq, i64 0, i64 0), i64 32)
  %l4 = call %Str @t2_concat(%Str %l2, %Str %l3)
  %l5 = call %Str @t2_concat(%Str %l4, %Str %vs)
  br label %die
nodef:
  %n0 = call %Str @t2_str(i8* getelementptr ([19 x i8], [19 x i8]* @lit_vnodef, i64 0, i64 0), i64 18)
  %n1 = call %Str @t2_concat(%Str %c, %Str %n0)
  %n2 = call %Str @t2_concat(%Str %n1, %Str %c)
  %n3 = call %Str @t2_str(i8* getelementptr ([32 x i8], [32 x i8]* @lit_vnodef2, i64 0, i64 0), i64 31)
  %n4 = call %Str @t2_concat(%Str %n2, %Str %n3)
  br label %die
neither:
  %e0 = call %Str @t2_str(i8* getelementptr ([59 x i8], [59 x i8]* @lit_vneither, i64 0, i64 0), i64 58)
  %e1 = call %Str @t2_concat(%Str %c, %Str %e0)
  br label %die
die:
  %m = phi %Str [ %l5, %low ], [ %n4, %nodef ], [ %e1, %neither ]
  %at = load %Str, %Str* @t2_call_at
  %full = call %Str @t2_concat(%Str %m, %Str %at)
  call void @t2_die_unwind(%Str %full)
  ret %Slot zeroinitializer
}
@lit_tm_fetchsize = private unnamed_addr constant [10 x i8] c"FETCHSIZE\00"
@lit_tm_fetch = private unnamed_addr constant [6 x i8] c"FETCH\00"
@lit_tm_store = private unnamed_addr constant [6 x i8] c"STORE\00"
@lit_tm_push = private unnamed_addr constant [5 x i8] c"PUSH\00"
@lit_tm_pop = private unnamed_addr constant [4 x i8] c"POP\00"
@lit_tm_shift = private unnamed_addr constant [6 x i8] c"SHIFT\00"
@lit_tm_unshift = private unnamed_addr constant [8 x i8] c"UNSHIFT\00"
@lit_tm_exists = private unnamed_addr constant [7 x i8] c"EXISTS\00"
@lit_tm_delete = private unnamed_addr constant [7 x i8] c"DELETE\00"
@lit_tm_firstkey = private unnamed_addr constant [9 x i8] c"FIRSTKEY\00"
@lit_tm_nextkey = private unnamed_addr constant [8 x i8] c"NEXTKEY\00"
@lit_tm_clear = private unnamed_addr constant [6 x i8] c"CLEAR\00"
@lit_tm_tiearray = private unnamed_addr constant [9 x i8] c"TIEARRAY\00"
@lit_tm_tiehash = private unnamed_addr constant [8 x i8] c"TIEHASH\00"
; THE CONTAINER PROTOCOL (perigrin: a tie swaps a container's metaobject).
; Every %Array -- an array, or a hash's pairs -- points at a metaobject:
; a vtable of its operations and a datum (a tie's object). The default's
; entries are the runtime's own functions (t2_aget_d, ...); t2_aget and the
; rest look the operation up there. A tie's entries call the object's
; methods; the other kind's entries stay the default's.
%Meta = type { i8**, %Slot }
@t2_vt_default = internal global [20 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_aget_d to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_aset_d to i8*),
  i8* bitcast (i64 (%Array*)* @t2_alen_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_apush_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_apop_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_ashift_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_aunshift_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aappend_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aunshiftl_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hget_d to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_hset_d to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_hexists_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hdelete_d to i8*),
  i8* bitcast (i64 (%Slot)* @t2_hcount_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hkeys_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hvalues_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hpairs_d to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_hfroma_d to i8*),
  i8* bitcast (i1 (%Array*, i64)* @t2_aexists_d to i8*),
  i8* bitcast (void (%Array*, i64)* @t2_aset_len_d to i8*)
]
@t2_vt_tiearray = internal global [20 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_tie_aget to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_tie_aset to i8*),
  i8* bitcast (i64 (%Array*)* @t2_tie_alen to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_tie_apush to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_tie_apop to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_tie_ashift to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_tie_aunshift to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_tie_aappend to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_tie_aunshiftl to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hget_d to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_hset_d to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_hexists_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hdelete_d to i8*),
  i8* bitcast (i64 (%Slot)* @t2_hcount_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hkeys_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hvalues_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hpairs_d to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_hfroma_d to i8*),
  i8* bitcast (i1 (%Array*, i64)* @t2_tie_aexists to i8*),
  i8* bitcast (void (%Array*, i64)* @t2_tie_aset_len to i8*)
]
@t2_vt_tiehash = internal global [20 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_aget_d to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_aset_d to i8*),
  i8* bitcast (i64 (%Array*)* @t2_alen_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_apush_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_apop_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_ashift_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_aunshift_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aappend_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aunshiftl_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_tie_hget to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_tie_hset to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_tie_hexists to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_tie_hdelete to i8*),
  i8* bitcast (i64 (%Slot)* @t2_tie_hcount to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hkeys to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hvalues to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hpairs to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_tie_hfroma to i8*),
  i8* bitcast (i1 (%Array*, i64)* @t2_aexists_d to i8*),
  i8* bitcast (void (%Array*, i64)* @t2_aset_len_d to i8*)
]
@t2_meta_default = internal global %Meta { i8** getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_default, i64 0, i64 0), %Slot zeroinitializer }
; t2_meta(a) -> the metaobject a container points at
define internal %Meta* @t2_meta(%Array* %a) {
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  %m = load %Meta*, %Meta** %mp
  ret %Meta* %m
}
define internal i8* @t2_vt(%Array* %a, i64 %k) {
  %m = call %Meta* @t2_meta(%Array* %a)
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  %vt = load i8**, i8*** %vp
  %fp = getelementptr i8*, i8** %vt, i64 %k
  %f = load i8*, i8** %fp
  ret i8* %f
}
define internal %Slot @t2_aget(%Array* %p0, i64 %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 0)
  %fn = bitcast i8* %f to %Slot (%Array*, i64)*
  %r = call %Slot %fn(%Array* %p0, i64 %p1)
  ret %Slot %r
}
define internal void @t2_aset(%Array* %p0, i64 %p1, %Slot %p2, i8* %p3, i64 %p4) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 1)
  %fn = bitcast i8* %f to void (%Array*, i64, %Slot, i8*, i64)*
  call void %fn(%Array* %p0, i64 %p1, %Slot %p2, i8* %p3, i64 %p4)
  ret void
}
define internal i64 @t2_alen(%Array* %p0) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 2)
  %fn = bitcast i8* %f to i64 (%Array*)*
  %r = call i64 %fn(%Array* %p0)
  ret i64 %r
}
define internal void @t2_apush(%Array* %p0, %Slot %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 3)
  %fn = bitcast i8* %f to void (%Array*, %Slot)*
  call void %fn(%Array* %p0, %Slot %p1)
  ret void
}
define internal %Slot @t2_apop(%Array* %p0) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 4)
  %fn = bitcast i8* %f to %Slot (%Array*)*
  %r = call %Slot %fn(%Array* %p0)
  ret %Slot %r
}
define internal %Slot @t2_ashift(%Array* %p0) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 5)
  %fn = bitcast i8* %f to %Slot (%Array*)*
  %r = call %Slot %fn(%Array* %p0)
  ret %Slot %r
}
define internal void @t2_aunshift(%Array* %p0, %Slot %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 6)
  %fn = bitcast i8* %f to void (%Array*, %Slot)*
  call void %fn(%Array* %p0, %Slot %p1)
  ret void
}
define internal void @t2_aappend(%Array* %p0, %Array* %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 7)
  %fn = bitcast i8* %f to void (%Array*, %Array*)*
  call void %fn(%Array* %p0, %Array* %p1)
  ret void
}
define internal void @t2_aunshiftl(%Array* %p0, %Array* %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 8)
  %fn = bitcast i8* %f to void (%Array*, %Array*)*
  call void %fn(%Array* %p0, %Array* %p1)
  ret void
}
; (a read through undef is undef, as perl's -- which makes the hash; a write
; through one B::SoN spells as the hash made first)
define internal %Slot @t2_hget(%Slot %p0, %Str %p1) {
entry:
  %t = extractvalue %Slot %p0, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %go
undef:
  ret %Slot zeroinitializer
go:
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 9)
  %fn = bitcast i8* %f to %Slot (%Slot, %Str)*
  %r = call %Slot %fn(%Slot %p0, %Str %p1)
  ret %Slot %r
}
define internal void @t2_hset(%Slot %p0, %Str %p1, %Slot %p2) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 10)
  %fn = bitcast i8* %f to void (%Slot, %Str, %Slot)*
  call void %fn(%Slot %p0, %Str %p1, %Slot %p2)
  ret void
}
define internal i1 @t2_hexists(%Slot %p0, %Str %p1) {
entry:
  %t = extractvalue %Slot %p0, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %go
undef:
  ret i1 0
go:
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 11)
  %fn = bitcast i8* %f to i1 (%Slot, %Str)*
  %r = call i1 %fn(%Slot %p0, %Str %p1)
  ret i1 %r
}
define internal %Slot @t2_hdelete(%Slot %p0, %Str %p1) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 12)
  %fn = bitcast i8* %f to %Slot (%Slot, %Str)*
  %r = call %Slot %fn(%Slot %p0, %Str %p1)
  ret %Slot %r
}
define internal i64 @t2_hcount(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 13)
  %fn = bitcast i8* %f to i64 (%Slot)*
  %r = call i64 %fn(%Slot %p0)
  ret i64 %r
}
define internal %Array* @t2_hkeys(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 14)
  %fn = bitcast i8* %f to %Array* (%Slot)*
  %r = call %Array* %fn(%Slot %p0)
  ret %Array* %r
}
define internal %Array* @t2_hvalues(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 15)
  %fn = bitcast i8* %f to %Array* (%Slot)*
  %r = call %Array* %fn(%Slot %p0)
  ret %Array* %r
}
define internal %Array* @t2_hpairs(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 16)
  %fn = bitcast i8* %f to %Array* (%Slot)*
  %r = call %Array* %fn(%Slot %p0)
  ret %Array* %r
}
define internal void @t2_hfroma(%Slot %p0, %Array* %p1) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 17)
  %fn = bitcast i8* %f to void (%Slot, %Array*)*
  call void %fn(%Slot %p0, %Array* %p1)
  ret void
}
; t2_tie_obj(a) -> the object a tied container's metaobject holds
define internal %Slot @t2_tie_obj(%Array* %a) {
  %m = call %Meta* @t2_meta(%Array* %a)
  %dp = getelementptr %Meta, %Meta* %m, i32 0, i32 1
  %d = load %Slot, %Slot* %dp
  ret %Slot %d
}
; t2_tie_call(args, name) -> the method name of args[0] called with args, in scalar context
define internal %Slot @t2_tie_call(%Array* %args, %Str %m) {
  %o = call %Slot @t2_aget(%Array* %args, i64 0)
  %e = call %Str @t2_str(i8* null, i64 0)
  %fp = call i8* @t2_mresolve(%Slot %o, %Str %m, %Str %e, %Str %e, i8 0)
  %w = load i1, i1* @t2_want
  store i1 0, i1* @t2_want
  %f = bitcast i8* %fp to %Slot (%Array*)*
  %r = call %Slot %f(%Array* %args)
  store i1 %w, i1* @t2_want
  ret %Slot %r
}
define internal i64 @t2_tie_alen(%Array* %p0) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t0.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t0.args, %Slot %o)
  %t0.m = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_tm_fetchsize, i64 0, i64 0), i64 9)
  %t0 = call %Slot @t2_tie_call(%Array* %t0.args, %Str %t0.m)
  %n = call i64 @t2_slot_i64(%Slot %t0)
  ret i64 %n
}
define internal %Slot @t2_tie_aget(%Array* %p0, i64 %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %neg = icmp slt i64 %p1, 0
  br i1 %neg, label %fix, label %go
fix:
  %sz = call i64 @t2_tie_alen(%Array* %a)
  %j0 = add i64 %p1, %sz
  br label %go
go:
  %j = phi i64 [ %p1, %entry ], [ %j0, %fix ]
  %js = call %Slot @t2_box_i64(i64 %j)
  %t1.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t1.args, %Slot %o)
  call void @t2_apush(%Array* %t1.args, %Slot %js)
  %t1.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t1 = call %Slot @t2_tie_call(%Array* %t1.args, %Str %t1.m)
  ret %Slot %t1
}
define internal void @t2_tie_aset(%Array* %p0, i64 %p1, %Slot %p2, i8* %p3, i64 %p4) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %neg = icmp slt i64 %p1, 0
  br i1 %neg, label %fix, label %go
fix:
  %sz = call i64 @t2_tie_alen(%Array* %a)
  %j0 = add i64 %p1, %sz
  br label %go
go:
  %j = phi i64 [ %p1, %entry ], [ %j0, %fix ]
  %js = call %Slot @t2_box_i64(i64 %j)
  %t2.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t2.args, %Slot %o)
  call void @t2_apush(%Array* %t2.args, %Slot %js)
  call void @t2_apush(%Array* %t2.args, %Slot %p2)
  %t2.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_store, i64 0, i64 0), i64 5)
  %t2 = call %Slot @t2_tie_call(%Array* %t2.args, %Str %t2.m)
  ret void
}
define internal void @t2_tie_apush(%Array* %p0, %Slot %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t3.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t3.args, %Slot %o)
  call void @t2_apush(%Array* %t3.args, %Slot %p1)
  %t3.m = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_tm_push, i64 0, i64 0), i64 4)
  %t3 = call %Slot @t2_tie_call(%Array* %t3.args, %Str %t3.m)
  ret void
}
define internal %Slot @t2_tie_apop(%Array* %p0) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t4.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t4.args, %Slot %o)
  %t4.m = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_tm_pop, i64 0, i64 0), i64 3)
  %t4 = call %Slot @t2_tie_call(%Array* %t4.args, %Str %t4.m)
  ret %Slot %t4
}
define internal %Slot @t2_tie_ashift(%Array* %p0) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t5.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t5.args, %Slot %o)
  %t5.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_shift, i64 0, i64 0), i64 5)
  %t5 = call %Slot @t2_tie_call(%Array* %t5.args, %Str %t5.m)
  ret %Slot %t5
}
define internal void @t2_tie_aunshift(%Array* %p0, %Slot %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t6.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t6.args, %Slot %o)
  call void @t2_apush(%Array* %t6.args, %Slot %p1)
  %t6.m = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_unshift, i64 0, i64 0), i64 7)
  %t6 = call %Slot @t2_tie_call(%Array* %t6.args, %Str %t6.m)
  ret void
}
define internal void @t2_tie_aappend(%Array* %p0, %Array* %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_aappend(%Array* %args, %Array* %p1)
  %m = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_tm_push, i64 0, i64 0), i64 4)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  ret void
}
define internal void @t2_tie_aunshiftl(%Array* %p0, %Array* %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_aappend(%Array* %args, %Array* %p1)
  %m = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_unshift, i64 0, i64 0), i64 7)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  ret void
}
define internal %Slot @t2_tie_hget(%Slot %p0, %Str %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t7.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t7.args, %Slot %o)
  call void @t2_apush(%Array* %t7.args, %Slot %ks)
  %t7.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t7 = call %Slot @t2_tie_call(%Array* %t7.args, %Str %t7.m)
  ret %Slot %t7
}
define internal void @t2_tie_hset(%Slot %p0, %Str %p1, %Slot %p2) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t8.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t8.args, %Slot %o)
  call void @t2_apush(%Array* %t8.args, %Slot %ks)
  call void @t2_apush(%Array* %t8.args, %Slot %p2)
  %t8.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_store, i64 0, i64 0), i64 5)
  %t8 = call %Slot @t2_tie_call(%Array* %t8.args, %Str %t8.m)
  ret void
}
define internal i1 @t2_tie_hexists(%Slot %p0, %Str %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t9.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t9.args, %Slot %o)
  call void @t2_apush(%Array* %t9.args, %Slot %ks)
  %t9.m = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_exists, i64 0, i64 0), i64 6)
  %t9 = call %Slot @t2_tie_call(%Array* %t9.args, %Str %t9.m)
  %b = call i1 @t2_truth_slot(%Slot %t9)
  ret i1 %b
}
define internal %Slot @t2_tie_hdelete(%Slot %p0, %Str %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t10.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t10.args, %Slot %o)
  call void @t2_apush(%Array* %t10.args, %Slot %ks)
  %t10.m = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_delete, i64 0, i64 0), i64 6)
  %t10 = call %Slot @t2_tie_call(%Array* %t10.args, %Str %t10.m)
  ret %Slot %t10
}
define internal %Array* @t2_tie_hkeys(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_new_array()
  %t11.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t11.args, %Slot %o)
  %t11.m = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_tm_firstkey, i64 0, i64 0), i64 8)
  %t11 = call %Slot @t2_tie_call(%Array* %t11.args, %Str %t11.m)
  br label %loop
loop:
  %k = phi %Slot [ %t11, %entry ], [ %t12, %more ]
  %kt = extractvalue %Slot %k, 0
  %done = icmp eq i8 %kt, 0
  br i1 %done, label %end, label %more
more:
  call void @t2_apush(%Array* %ks, %Slot %k)
  %t12.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t12.args, %Slot %o)
  call void @t2_apush(%Array* %t12.args, %Slot %k)
  %t12.m = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_nextkey, i64 0, i64 0), i64 7)
  %t12 = call %Slot @t2_tie_call(%Array* %t12.args, %Str %t12.m)
  br label %loop
end:
  ret %Array* %ks
}
define internal i64 @t2_tie_hcount(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_tie_hkeys(%Slot %p0)
  %n = call i64 @t2_alen(%Array* %ks)
  ret i64 %n
}
define internal %Array* @t2_tie_hvalues(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_tie_hkeys(%Slot %p0)
  %n = call i64 @t2_alen(%Array* %ks)
  %out = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %go = icmp slt i64 %i, %n
  br i1 %go, label %body, label %end
body:
  %k = call %Slot @t2_aget(%Array* %ks, i64 %i)
  %t13.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t13.args, %Slot %o)
  call void @t2_apush(%Array* %t13.args, %Slot %k)
  %t13.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t13 = call %Slot @t2_tie_call(%Array* %t13.args, %Str %t13.m)
  call void @t2_apush(%Array* %out, %Slot %t13)
  %i2 = add i64 %i, 1
  br label %loop
end:
  ret %Array* %out
}
define internal %Array* @t2_tie_hpairs(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_tie_hkeys(%Slot %p0)
  %n = call i64 @t2_alen(%Array* %ks)
  %out = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %go = icmp slt i64 %i, %n
  br i1 %go, label %body, label %end
body:
  %k = call %Slot @t2_aget(%Array* %ks, i64 %i)
  call void @t2_apush(%Array* %out, %Slot %k)
  %t14.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t14.args, %Slot %o)
  call void @t2_apush(%Array* %t14.args, %Slot %k)
  %t14.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t14 = call %Slot @t2_tie_call(%Array* %t14.args, %Str %t14.m)
  call void @t2_apush(%Array* %out, %Slot %t14)
  %i2 = add i64 %i, 1
  br label %loop
end:
  ret %Array* %out
}
define internal void @t2_tie_hfroma(%Slot %p0, %Array* %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t15.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t15.args, %Slot %o)
  %t15.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_clear, i64 0, i64 0), i64 5)
  %t15 = call %Slot @t2_tie_call(%Array* %t15.args, %Str %t15.m)
  %n = call i64 @t2_alen(%Array* %p1)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %go = icmp slt i64 %i, %n
  br i1 %go, label %body, label %end
body:
  %k = call %Slot @t2_aget(%Array* %p1, i64 %i)
  %i1 = add i64 %i, 1
  %val = call %Slot @t2_aget(%Array* %p1, i64 %i1)
  %t16.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t16.args, %Slot %o)
  call void @t2_apush(%Array* %t16.args, %Slot %k)
  call void @t2_apush(%Array* %t16.args, %Slot %val)
  %t16.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_store, i64 0, i64 0), i64 5)
  %t16 = call %Slot @t2_tie_call(%Array* %t16.args, %Str %t16.m)
  %i2 = add i64 %i, 2
  br label %loop
end:
  ret void
}
; t2_tie(a, vt, class, args, ctor) -> the object ctor (TIEARRAY/TIEHASH) made; a now points at a tie's metaobject holding it
define internal %Slot @t2_tie(%Array* %a, i8** %vt, %Slot %cls, %Array* %rest, %Str %ctor) {
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %cls)
  call void @t2_aappend(%Array* %args, %Array* %rest)
  %o = call %Slot @t2_tie_call(%Array* %args, %Str %ctor)
  %mm = call i8* @malloc(i64 32)
  %m = bitcast i8* %mm to %Meta*
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  store i8** %vt, i8*** %vp
  %dp = getelementptr %Meta, %Meta* %m, i32 0, i32 1
  store %Slot %o, %Slot* %dp
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* %m, %Meta** %mp
  ret %Slot %o
}
define internal %Slot @t2_tie_array(%Array* %a, %Slot %cls, %Array* %rest) {
  %c = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_tm_tiearray, i64 0, i64 0), i64 8)
  %r = call %Slot @t2_tie(%Array* %a, i8** getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_tiearray, i64 0, i64 0), %Slot %cls, %Array* %rest, %Str %c)
  ret %Slot %r
}
define internal %Slot @t2_tie_hash(%Slot %h, %Slot %cls, %Array* %rest) {
  %a = call %Array* @t2_harr(%Slot %h)
  %c = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_tiehash, i64 0, i64 0), i64 7)
  %r = call %Slot @t2_tie(%Array* %a, i8** getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_tiehash, i64 0, i64 0), %Slot %cls, %Array* %rest, %Str %c)
  ret %Slot %r
}
; t2_tied(a) -> the tie's object, or undef where a has the default metaobject
define internal %Slot @t2_tied(%Array* %a) {
entry:
  %m = call %Meta* @t2_meta(%Array* %a)
  %d = icmp eq %Meta* %m, @t2_meta_default
  br i1 %d, label %no, label %yes
no:
  ret %Slot zeroinitializer
yes:
  %o = call %Slot @t2_tie_obj(%Array* %a)
  ret %Slot %o
}
; t2_untie(a): a back to the default metaobject (its own elements, untouched by the tie)
define internal void @t2_untie(%Array* %a) {
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* @t2_meta_default, %Meta** %mp
  ret void
}
define internal void @t2_aunshiftl_d(%Array* %a, %Array* %l) {
entry:
  %n = call i64 @t2_alen(%Array* %l)
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %l, i64 %im)
  call void @t2_aunshift_d(%Array* %a, %Slot %v)
  br label %loop
done:
  ret void
}
define internal %Slot @t2_tied_h(%Slot %h) {
  %a = call %Array* @t2_harr(%Slot %h)
  %r = call %Slot @t2_tied(%Array* %a)
  ret %Slot %r
}
define internal void @t2_untie_h(%Slot %h) {
  %a = call %Array* @t2_harr(%Slot %h)
  call void @t2_untie(%Array* %a)
  ret void
}
; t2_args_from(a, k) -> a fresh array of a's elements from k on (a slurpy's copy).
define internal %Array* @t2_args_from(%Array* %a, i64 %k) {
entry:
  %r = call %Array* @t2_new_array()
  %n = call i64 @t2_alen(%Array* %a)
  br label %loop
loop:
  %i = phi i64 [ %k, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
; t2_args_pairs(a, n): a signature's slurpy hash takes pairs -- an odd count
; past n is a stop (perl dies: "Odd name/value argument").
define internal void @t2_args_pairs(%Array* %a, i64 %n) {
entry:
  %got = call i64 @t2_alen(%Array* %a)
  %rest = sub i64 %got, %n
  %odd = and i64 %rest, 1
  %bad = icmp ne i64 %odd, 0
  br i1 %bad, label %stop, label %fine
stop:
  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)
  unreachable
fine:
  ret void
}
; t2_args_min(a, n): a signature's arity -- at least n arguments, else a stop.
define internal void @t2_args_min(%Array* %a, i64 %n) {
entry:
  %got = call i64 @t2_alen(%Array* %a)
  %ok = icmp sge i64 %got, %n
  br i1 %ok, label %fine, label %bad
bad:
  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)
  unreachable
fine:
  ret void
}
; t2_cmp(x, y, num) -> perl's cmp (by string) or <=> (by number): -1, 0, 1.
define internal i64 @t2_cmp(%Slot %x, %Slot %y, i1 %num) {
entry:
  br i1 %num, label %n, label %s
n:
  ; (two Ints compared as integers: past 2**53 a double cannot tell them apart)
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %ix = icmp eq i8 %tx, 1
  %iy = icmp eq i8 %ty, 1
  %both = and i1 %ix, %iy
  br i1 %both, label %ints, label %nums
ints:
  %vx = extractvalue %Slot %x, 1
  %vy = extractvalue %Slot %y, 1
  %ilt = icmp slt i64 %vx, %vy
  %igt = icmp sgt i64 %vx, %vy
  %il = select i1 %ilt, i64 -1, i64 0
  %ir = select i1 %igt, i64 1, i64 %il
  ret i64 %ir
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %lt = fcmp olt double %dx, %dy
  %gt = fcmp ogt double %dx, %dy
  %l = select i1 %lt, i64 -1, i64 0
  %r = select i1 %gt, i64 1, i64 %l
  ret i64 %r
s:
  %sx = call %Str @t2_slot_str(%Slot %x)
  %sy = call %Str @t2_slot_str(%Slot %y)
  %c = call i64 @t2_strcmp(%Str %sx, %Str %sy)
  %neg = icmp slt i64 %c, 0
  %pos = icmp sgt i64 %c, 0
  %c1 = select i1 %neg, i64 -1, i64 0
  %c2 = select i1 %pos, i64 1, i64 %c1
  ret i64 %c2
}
; t2_hderef_r(r) -> the hash r holds, read whole; undef an empty hash (perl's
; rvalue +(undef)->%*). What is not a hash stops at its first access.
define internal %Slot @t2_hderef_r(%Slot %r) {
entry:
  %t = extractvalue %Slot %r, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %empty, label %as
empty:
  %h = call %Slot @t2_hnew()
  ret %Slot %h
as:
  ret %Slot %r
}
; t2_asort(a, num, desc) -> a new list of a's elements in order (stable, as
; perl's mergesort is).
define internal %Array* @t2_asort(%Array* %a, i1 %num, i1 %desc) {
entry:
  %r = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %r, %Array* %a)
  %n = call i64 @t2_alen(%Array* %r)
  br label %outer
outer:
  %i = phi i64 [ 1, %entry ], [ %i2, %placed ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %take, label %done
take:
  %v = call %Slot @t2_aget(%Array* %r, i64 %i)
  br label %inner
inner:
  %j = phi i64 [ %i, %take ], [ %jm, %shift ]
  %atstart = icmp eq i64 %j, 0
  br i1 %atstart, label %place, label %look
look:
  %jm = sub i64 %j, 1
  %p = call %Slot @t2_aget(%Array* %r, i64 %jm)
  %c0 = call i64 @t2_cmp(%Slot %p, %Slot %v, i1 %num)
  %cn = sub i64 0, %c0
  %c = select i1 %desc, i64 %cn, i64 %c0
  %after = icmp sgt i64 %c, 0
  br i1 %after, label %shift, label %place
shift:
  call void @t2_aset(%Array* %r, i64 %j, %Slot %p, i8* null, i64 0)
  br label %inner
place:
  call void @t2_aset(%Array* %r, i64 %j, %Slot %v, i8* null, i64 0)
  br label %placed
placed:
  %i2 = add i64 %i, 1
  br label %outer
done:
  ret %Array* %r
}
; t2_asort_by(a, f, ga, gb) -> a new list of a's elements in the order f
; gives: for each pair $a (ga) and $b (gb) are set, f called, and a number
; above 0 puts $a after $b (stable). $a and $b are as they were after.
@t2_cmp_env = internal global %Array* null
define internal %Slot @t2_cmp_env_at(i64 %i) {
  %e = load %Array*, %Array** @t2_cmp_env
  %s = call %Slot @t2_aget(%Array* %e, i64 %i)
  ret %Slot %s
}
@t2_cur_cmp = internal global %Slot ()* null
@t2_cur_ga = internal global %Slot* null
@t2_cur_gb = internal global %Slot* null
; t2_sort_cmp_ab(a, b): the comparator on a pair -- $a and $b set, it called,
; its number given; one that dies leaves the sort (t2_msort_abort).
define double @t2_sort_cmp_ab(%Slot* %a, %Slot* %b) {
entry:
  %ga = load %Slot*, %Slot** @t2_cur_ga
  %gb = load %Slot*, %Slot** @t2_cur_gb
  %va = load %Slot, %Slot* %a
  %vb = load %Slot, %Slot* %b
  store %Slot %va, %Slot* %ga
  store %Slot %vb, %Slot* %gb
  %f = load %Slot ()*, %Slot ()** @t2_cur_cmp
  %c = call %Slot %f()
  %d = load i1, i1* @t2_dying
  br i1 %d, label %die, label %ok
die:
  call void @t2_msort_abort()
  unreachable
ok:
  %n = call double @t2_slot_num(%Slot %c)
  ret double %n
}
; t2_asort_by(a, env, f, ga, gb) -> a new list of a's elements in the order
; f gives, compared as perl's sort compares (pp_sort.c, ported: t2_msort) --
; the same pairs in the same order, so a comparator's effects are perl's.
; $a, $b, the env and the comparator are as they were after.
define internal %Array* @t2_asort_by(%Array* %a, %Array* %env, %Slot ()* %f, %Slot* %ga, %Slot* %gb) {
entry:
  %oe = load %Array*, %Array** @t2_cmp_env
  %oa = load %Slot, %Slot* %ga
  %ob = load %Slot, %Slot* %gb
  %of = load %Slot ()*, %Slot ()** @t2_cur_cmp
  %oga = load %Slot*, %Slot** @t2_cur_ga
  %ogb = load %Slot*, %Slot** @t2_cur_gb
  store %Array* %env, %Array** @t2_cmp_env
  store %Slot ()* %f, %Slot ()** @t2_cur_cmp
  store %Slot* %ga, %Slot** @t2_cur_ga
  store %Slot* %gb, %Slot** @t2_cur_gb
  %r = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %r, %Array* %a)
  %n = call i64 @t2_alen(%Array* %r)
  %ep = getelementptr %Array, %Array* %r, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %died = call i32 @t2_msort(%Slot* %els, i64 %n)
  store %Slot %oa, %Slot* %ga
  store %Slot %ob, %Slot* %gb
  store %Slot ()* %of, %Slot ()** @t2_cur_cmp
  store %Slot* %oga, %Slot** @t2_cur_ga
  store %Slot* %ogb, %Slot** @t2_cur_gb
  store %Array* %oe, %Array** @t2_cmp_env
  ret %Array* %r
}
; ---- perl's sort, ported to C (pp_sort.c's dynprep and merge) and compiled ----

%struct.off_runs = type { i64, i64 }
%struct.__jmp_buf_tag = type { [8 x i64], i32, %struct.__sigset_t }
%struct.__sigset_t = type { [16 x i64] }
%struct.Slot = type { i8, i64 }

@msort_jb = internal unnamed_addr global ptr null, align 8

; Function Attrs: noreturn nounwind uwtable
define dso_local void @t2_msort_abort() local_unnamed_addr #0 {
  %1 = load ptr, ptr @msort_jb, align 8
  tail call void @longjmp(ptr noundef %1, i32 noundef 1) #10
  unreachable
}

; Function Attrs: noreturn nounwind
declare void @longjmp(ptr noundef, i32 noundef) local_unnamed_addr #1

; Function Attrs: nounwind uwtable
define dso_local noundef i32 @t2_msort(ptr nocapture noundef %0, i64 noundef %1) local_unnamed_addr #2 {
  %3 = alloca [200 x ptr], align 16
  %4 = alloca [3 x ptr], align 16
  %5 = alloca [60 x %struct.off_runs], align 16
  %6 = alloca [1 x %struct.__jmp_buf_tag], align 16
  %7 = call i64 @llvm.umax.i64(i64 %1, i64 1)
  %8 = shl i64 %7, 3
  %9 = call noalias ptr @malloc(i64 noundef %8) #11
  %10 = shl i64 %7, 4
  %11 = call noalias ptr @malloc(i64 noundef %10) #11
  call void @llvm.lifetime.start.p0(i64 200, ptr nonnull %6) #12
  %12 = load ptr, ptr @msort_jb, align 8
  %13 = icmp sgt i64 %1, 0
  br i1 %13, label %14, label %16

14:                                               ; preds = %2
  %15 = shl nuw i64 %1, 4
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %11, ptr align 8 %0, i64 %15, i1 false)
  br label %19

16:                                               ; preds = %19, %2
  store ptr %6, ptr @msort_jb, align 8
  %17 = call i32 @_setjmp(ptr noundef nonnull %6) #13
  %18 = icmp eq i32 %17, 0
  br i1 %18, label %25, label %508

19:                                               ; preds = %14, %19
  %20 = phi i64 [ %23, %19 ], [ 0, %14 ]
  %21 = getelementptr inbounds %struct.Slot, ptr %11, i64 %20
  %22 = getelementptr inbounds ptr, ptr %9, i64 %20
  store ptr %21, ptr %22, align 8
  %23 = add nuw nsw i64 %20, 1
  %24 = icmp eq i64 %23, %1
  br i1 %24, label %16, label %19

25:                                               ; preds = %16
  %26 = ptrtoint ptr %9 to i64
  call void @llvm.lifetime.start.p0(i64 1600, ptr nonnull %3) #12
  call void @llvm.lifetime.start.p0(i64 24, ptr nonnull %4) #12
  call void @llvm.lifetime.start.p0(i64 960, ptr nonnull %5) #12
  %27 = icmp ult i64 %1, 2
  br i1 %27, label %499, label %28

28:                                               ; preds = %25
  %29 = icmp ult i64 %1, 201
  br i1 %29, label %33, label %30

30:                                               ; preds = %28
  %31 = shl i64 %1, 3
  %32 = call noalias ptr @malloc(i64 noundef %31) #11
  br label %33

33:                                               ; preds = %30, %28
  %34 = phi ptr [ %32, %30 ], [ %3, %28 ]
  %35 = getelementptr inbounds ptr, ptr %9, i64 %1
  %36 = load ptr, ptr %9, align 8
  %37 = getelementptr inbounds ptr, ptr %9, i64 1
  %38 = load ptr, ptr %37, align 8
  %39 = call double @t2_sort_cmp_ab(ptr noundef %36, ptr noundef %38) #12
  %40 = icmp sgt i64 %1, 0
  br i1 %40, label %41, label %192

41:                                               ; preds = %33
  %42 = fcmp oge double %39, 9.200000e+18
  %43 = fcmp ugt double %39, -9.200000e+18
  %44 = fptosi double %39 to i64
  %45 = icmp sgt i64 %44, 0
  %46 = select i1 %43, i1 %45, i1 false
  %47 = select i1 %42, i1 true, i1 %46
  br label %48

48:                                               ; preds = %189, %41
  %49 = phi i1 [ %190, %189 ], [ %47, %41 ]
  %50 = phi ptr [ %187, %189 ], [ %9, %41 ]
  %51 = phi i64 [ %186, %189 ], [ 0, %41 ]
  %52 = phi ptr [ %177, %189 ], [ %34, %41 ]
  br label %53

53:                                               ; preds = %58, %48
  %54 = phi ptr [ %55, %58 ], [ %50, %48 ]
  %55 = getelementptr inbounds ptr, ptr %54, i64 2
  %56 = getelementptr inbounds ptr, ptr %54, i64 3
  %57 = icmp ult ptr %56, %35
  br i1 %57, label %58, label %69

58:                                               ; preds = %53
  %59 = load ptr, ptr %55, align 8
  %60 = load ptr, ptr %56, align 8
  %61 = call double @t2_sort_cmp_ab(ptr noundef %59, ptr noundef %60) #12
  %62 = fcmp ult double %61, 9.200000e+18
  %63 = fcmp ole double %61, -9.200000e+18
  %64 = fptosi double %61 to i64
  %65 = icmp slt i64 %64, 1
  %66 = select i1 %63, i1 true, i1 %65
  %67 = select i1 %62, i1 %66, i1 false
  %68 = xor i1 %49, %67
  br i1 %68, label %53, label %69

69:                                               ; preds = %58, %53
  %70 = icmp eq ptr %56, %35
  br label %71

71:                                               ; preds = %185, %69
  %72 = phi ptr [ %50, %69 ], [ %160, %185 ]
  %73 = phi ptr [ %52, %69 ], [ %177, %185 ]
  %74 = phi i64 [ %51, %69 ], [ %186, %185 ]
  %75 = phi ptr [ %50, %69 ], [ %187, %185 ]
  %76 = getelementptr inbounds ptr, ptr %75, i64 16
  %77 = icmp ult ptr %76, %55
  br i1 %77, label %78, label %113

78:                                               ; preds = %71, %91
  %79 = phi ptr [ %92, %91 ], [ %76, %71 ]
  %80 = getelementptr inbounds ptr, ptr %79, i64 -1
  %81 = load ptr, ptr %80, align 8
  %82 = load ptr, ptr %79, align 8
  %83 = call double @t2_sort_cmp_ab(ptr noundef %81, ptr noundef %82) #12
  %84 = fcmp ult double %83, 9.200000e+18
  %85 = fcmp ole double %83, -9.200000e+18
  %86 = fptosi double %83 to i64
  %87 = icmp slt i64 %86, 1
  %88 = select i1 %85, i1 true, i1 %87
  %89 = select i1 %84, i1 %88, i1 false
  %90 = xor i1 %49, %89
  br i1 %90, label %91, label %94

91:                                               ; preds = %78
  %92 = getelementptr inbounds ptr, ptr %79, i64 -2
  %93 = icmp ugt ptr %92, %72
  br i1 %93, label %78, label %94

94:                                               ; preds = %91, %78
  %95 = phi ptr [ %92, %91 ], [ %79, %78 ]
  %96 = icmp ugt ptr %95, %72
  br i1 %96, label %113, label %97

97:                                               ; preds = %94, %101
  %98 = phi ptr [ %99, %101 ], [ %76, %94 ]
  %99 = getelementptr inbounds ptr, ptr %98, i64 2
  %100 = icmp ult ptr %98, %54
  br i1 %100, label %101, label %113

101:                                              ; preds = %97
  %102 = getelementptr inbounds ptr, ptr %98, i64 1
  %103 = load ptr, ptr %102, align 8
  %104 = load ptr, ptr %99, align 8
  %105 = call double @t2_sort_cmp_ab(ptr noundef %103, ptr noundef %104) #12
  %106 = fcmp ult double %105, 9.200000e+18
  %107 = fcmp ole double %105, -9.200000e+18
  %108 = fptosi double %105 to i64
  %109 = icmp slt i64 %108, 1
  %110 = select i1 %107, i1 true, i1 %109
  %111 = select i1 %106, i1 %110, i1 false
  %112 = xor i1 %49, %111
  br i1 %112, label %97, label %113

113:                                              ; preds = %101, %97, %94, %71
  %114 = phi ptr [ %72, %94 ], [ %72, %71 ], [ %98, %97 ], [ %98, %101 ]
  %115 = phi ptr [ %95, %94 ], [ %55, %71 ], [ %99, %97 ], [ %99, %101 ]
  %116 = phi ptr [ %76, %94 ], [ %55, %71 ], [ %99, %97 ], [ %99, %101 ]
  %117 = icmp ugt ptr %114, %75
  br i1 %117, label %118, label %156

118:                                              ; preds = %113
  %119 = getelementptr inbounds ptr, ptr %114, i64 2
  %120 = icmp eq ptr %114, %54
  %121 = select i1 %120, i1 %70, i1 false
  br i1 %121, label %122, label %135

122:                                              ; preds = %118
  %123 = getelementptr inbounds ptr, ptr %114, i64 1
  %124 = load ptr, ptr %123, align 8
  %125 = load ptr, ptr %119, align 8
  %126 = call double @t2_sort_cmp_ab(ptr noundef %124, ptr noundef %125) #12
  %127 = fcmp ult double %126, 9.200000e+18
  %128 = fcmp ole double %126, -9.200000e+18
  %129 = fptosi double %126 to i64
  %130 = icmp slt i64 %129, 1
  %131 = select i1 %128, i1 true, i1 %130
  %132 = select i1 %127, i1 %131, i1 false
  %133 = xor i1 %49, %132
  br i1 %133, label %134, label %135

134:                                              ; preds = %122
  br label %135

135:                                              ; preds = %134, %122, %118
  %136 = phi ptr [ %35, %134 ], [ %119, %122 ], [ %119, %118 ]
  %137 = phi ptr [ %35, %134 ], [ %116, %122 ], [ %116, %118 ]
  %138 = phi ptr [ %35, %134 ], [ %115, %122 ], [ %115, %118 ]
  %139 = ptrtoint ptr %136 to i64
  %140 = ptrtoint ptr %75 to i64
  %141 = sub i64 %139, %140
  %142 = ashr exact i64 %141, 3
  %143 = getelementptr inbounds ptr, ptr %73, i64 %142
  store ptr %143, ptr %73, align 8
  %144 = add nsw i64 %74, 1
  %145 = getelementptr inbounds ptr, ptr %136, i64 -1
  %146 = icmp ult ptr %75, %145
  %147 = select i1 %49, i1 %146, i1 false
  br i1 %147, label %148, label %156

148:                                              ; preds = %135, %148
  %149 = phi ptr [ %154, %148 ], [ %145, %135 ]
  %150 = phi ptr [ %153, %148 ], [ %75, %135 ]
  %151 = load ptr, ptr %150, align 8
  %152 = load ptr, ptr %149, align 8
  %153 = getelementptr inbounds ptr, ptr %150, i64 1
  store ptr %152, ptr %150, align 8
  store ptr %151, ptr %149, align 8
  %154 = getelementptr inbounds ptr, ptr %149, i64 -1
  %155 = icmp ult ptr %153, %154
  br i1 %155, label %148, label %156

156:                                              ; preds = %148, %135, %113
  %157 = phi ptr [ %114, %113 ], [ %136, %135 ], [ %136, %148 ]
  %158 = phi ptr [ %73, %113 ], [ %143, %135 ], [ %143, %148 ]
  %159 = phi ptr [ %115, %113 ], [ %138, %135 ], [ %138, %148 ]
  %160 = phi ptr [ %116, %113 ], [ %137, %135 ], [ %137, %148 ]
  %161 = phi i64 [ %74, %113 ], [ %144, %135 ], [ %144, %148 ]
  %162 = icmp ult ptr %157, %159
  br i1 %162, label %163, label %176

163:                                              ; preds = %156, %173
  %164 = phi i64 [ %168, %173 ], [ %161, %156 ]
  %165 = phi ptr [ %167, %173 ], [ %158, %156 ]
  %166 = phi ptr [ %174, %173 ], [ %157, %156 ]
  %167 = getelementptr inbounds ptr, ptr %165, i64 2
  store ptr %167, ptr %165, align 8
  %168 = add nsw i64 %164, 1
  br i1 %49, label %169, label %173

169:                                              ; preds = %163
  %170 = getelementptr inbounds ptr, ptr %166, i64 1
  %171 = load ptr, ptr %166, align 8
  %172 = load ptr, ptr %170, align 8
  store ptr %172, ptr %166, align 8
  store ptr %171, ptr %170, align 8
  br label %173

173:                                              ; preds = %169, %163
  %174 = getelementptr inbounds ptr, ptr %166, i64 2
  %175 = icmp ult ptr %174, %159
  br i1 %175, label %163, label %176

176:                                              ; preds = %173, %156
  %177 = phi ptr [ %158, %156 ], [ %167, %173 ]
  %178 = phi i64 [ %161, %156 ], [ %168, %173 ]
  %179 = icmp eq ptr %159, %55
  %180 = select i1 %179, i1 %70, i1 false
  br i1 %180, label %181, label %185

181:                                              ; preds = %176
  %182 = getelementptr inbounds ptr, ptr %177, i64 1
  store ptr %182, ptr %177, align 8
  %183 = add nsw i64 %178, 1
  %184 = getelementptr inbounds ptr, ptr %159, i64 1
  br label %185

185:                                              ; preds = %181, %176
  %186 = phi i64 [ %183, %181 ], [ %178, %176 ]
  %187 = phi ptr [ %184, %181 ], [ %159, %176 ]
  %188 = icmp ult ptr %187, %55
  br i1 %188, label %71, label %189

189:                                              ; preds = %185
  %190 = xor i1 %49, true
  %191 = icmp ult ptr %187, %35
  br i1 %191, label %48, label %192

192:                                              ; preds = %189, %33
  %193 = phi i64 [ 0, %33 ], [ %186, %189 ]
  %194 = getelementptr inbounds %struct.off_runs, ptr %5, i64 0, i32 1
  store i64 %193, ptr %194, align 8
  store i64 0, ptr %5, align 16
  %195 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 2
  store ptr %9, ptr %195, align 16
  store ptr %9, ptr %4, align 16
  %196 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 1
  store ptr %34, ptr %196, align 8
  %197 = ptrtoint ptr %34 to i64
  %198 = xor i64 %26, -1
  %199 = sub i64 %26, %197
  %200 = add i64 %26, 8
  br label %201

201:                                              ; preds = %491, %192
  %202 = phi i64 [ 0, %192 ], [ %492, %491 ]
  %203 = phi i32 [ 0, %192 ], [ %493, %491 ]
  %204 = phi ptr [ %5, %192 ], [ %494, %491 ]
  %205 = getelementptr inbounds %struct.off_runs, ptr %204, i64 0, i32 1
  %206 = load i64, ptr %205, align 8
  %207 = icmp eq i64 %206, 0
  br i1 %207, label %208, label %422

208:                                              ; preds = %201
  %209 = and i32 %203, 1
  %210 = zext nneg i32 %209 to i64
  %211 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 %210
  %212 = load ptr, ptr %211, align 8
  %213 = add nuw nsw i32 %209, 1
  %214 = zext nneg i32 %213 to i64
  %215 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 %214
  %216 = load ptr, ptr %215, align 8
  br label %217

217:                                              ; preds = %412, %208
  %218 = phi i32 [ %203, %208 ], [ %403, %412 ]
  %219 = phi ptr [ %204, %208 ], [ %408, %412 ]
  %220 = phi ptr [ %212, %208 ], [ %410, %412 ]
  %221 = phi ptr [ %216, %208 ], [ %411, %412 ]
  %222 = load i64, ptr %219, align 8
  %223 = getelementptr inbounds ptr, ptr %220, i64 %222
  %224 = getelementptr inbounds ptr, ptr %221, i64 %222
  %225 = load ptr, ptr %224, align 8
  %226 = ptrtoint ptr %225 to i64
  %227 = ptrtoint ptr %221 to i64
  %228 = sub i64 %226, %227
  %229 = getelementptr inbounds i8, ptr %220, i64 %228
  %230 = load ptr, ptr %225, align 8
  %231 = ptrtoint ptr %230 to i64
  %232 = sub i64 %231, %227
  %233 = getelementptr inbounds i8, ptr %220, i64 %232
  %234 = icmp ult ptr %223, %229
  %235 = icmp slt i64 %228, %232
  %236 = select i1 %234, i1 %235, i1 false
  br i1 %236, label %237, label %377

237:                                              ; preds = %217, %366
  %238 = phi ptr [ %373, %366 ], [ %224, %217 ]
  %239 = phi ptr [ %370, %366 ], [ %229, %217 ]
  %240 = phi ptr [ %369, %366 ], [ %223, %217 ]
  %241 = load ptr, ptr %240, align 8
  %242 = load ptr, ptr %239, align 8
  %243 = call double @t2_sort_cmp_ab(ptr noundef %241, ptr noundef %242) #12
  %244 = fcmp ult double %243, 9.200000e+18
  %245 = fcmp ole double %243, -9.200000e+18
  %246 = fptosi double %243 to i64
  %247 = icmp slt i64 %246, 1
  %248 = select i1 %245, i1 true, i1 %247
  %249 = select i1 %244, i1 %248, i1 false
  %250 = sext i1 %249 to i32
  %251 = select i1 %249, ptr %229, ptr %233
  %252 = select i1 %249, ptr %240, ptr %239
  %253 = select i1 %249, ptr %239, ptr %240
  %254 = getelementptr inbounds ptr, ptr %252, i64 1
  %255 = icmp ult ptr %254, %251
  br i1 %255, label %256, label %270

256:                                              ; preds = %237
  %257 = load ptr, ptr %253, align 8
  %258 = load ptr, ptr %254, align 8
  %259 = call double @t2_sort_cmp_ab(ptr noundef %257, ptr noundef %258) #12
  %260 = fcmp ult double %259, 9.200000e+18
  %261 = fcmp ole double %259, -9.200000e+18
  %262 = fptosi double %259 to i64
  %263 = select i1 %261, i64 -1, i64 %262
  %264 = select i1 %260, i64 %263, i64 1
  %265 = icmp sgt i64 %264, -1
  %266 = icmp ne i64 %264, 0
  %267 = zext i1 %266 to i32
  %268 = icmp sgt i32 %267, %250
  %269 = and i1 %265, %268
  br i1 %269, label %304, label %313

270:                                              ; preds = %304, %237
  %271 = phi ptr [ %252, %237 ], [ %307, %304 ]
  %272 = getelementptr inbounds ptr, ptr %251, i64 -1
  %273 = icmp ugt ptr %272, %271
  br i1 %273, label %274, label %288

274:                                              ; preds = %270
  %275 = load ptr, ptr %253, align 8
  %276 = load ptr, ptr %272, align 8
  %277 = call double @t2_sort_cmp_ab(ptr noundef %275, ptr noundef %276) #12
  %278 = fcmp ult double %277, 9.200000e+18
  %279 = fcmp ole double %277, -9.200000e+18
  %280 = fptosi double %277 to i64
  %281 = select i1 %279, i64 -1, i64 %280
  %282 = select i1 %278, i64 %281, i64 1
  %283 = icmp sgt i64 %282, -1
  %284 = icmp ne i64 %282, 0
  %285 = zext i1 %284 to i32
  %286 = icmp sgt i32 %285, %250
  %287 = and i1 %283, %286
  br i1 %287, label %288, label %313

288:                                              ; preds = %274, %270
  br label %313

289:                                              ; preds = %304
  %290 = add nuw nsw i64 %305, 1
  %291 = load ptr, ptr %253, align 8
  %292 = load ptr, ptr %311, align 8
  %293 = call double @t2_sort_cmp_ab(ptr noundef %291, ptr noundef %292) #12
  %294 = fcmp ult double %293, 9.200000e+18
  %295 = fcmp ole double %293, -9.200000e+18
  %296 = fptosi double %293 to i64
  %297 = select i1 %295, i64 -1, i64 %296
  %298 = select i1 %294, i64 %297, i64 1
  %299 = icmp sgt i64 %298, -1
  %300 = icmp ne i64 %298, 0
  %301 = zext i1 %300 to i32
  %302 = icmp sgt i32 %301, %250
  %303 = and i1 %299, %302
  br i1 %303, label %304, label %313

304:                                              ; preds = %256, %289
  %305 = phi i64 [ %290, %289 ], [ 0, %256 ]
  %306 = phi i64 [ %310, %289 ], [ 1, %256 ]
  %307 = phi ptr [ %311, %289 ], [ %254, %256 ]
  %308 = icmp ugt i64 %305, 4
  %309 = zext i1 %308 to i64
  %310 = shl nsw i64 %306, %309
  %311 = getelementptr inbounds ptr, ptr %307, i64 %310
  %312 = icmp ult ptr %311, %251
  br i1 %312, label %289, label %270

313:                                              ; preds = %289, %256, %288, %274
  %314 = phi ptr [ %251, %288 ], [ %272, %274 ], [ %254, %256 ], [ %311, %289 ]
  %315 = phi ptr [ %272, %288 ], [ %271, %274 ], [ %252, %256 ], [ %307, %289 ]
  %316 = getelementptr inbounds ptr, ptr %315, i64 1
  %317 = icmp ult ptr %316, %314
  br i1 %317, label %318, label %345

318:                                              ; preds = %313, %318
  %319 = phi ptr [ %343, %318 ], [ %316, %313 ]
  %320 = phi ptr [ %342, %318 ], [ %314, %313 ]
  %321 = ptrtoint ptr %320 to i64
  %322 = ptrtoint ptr %319 to i64
  %323 = sub i64 %321, %322
  %324 = ashr exact i64 %323, 3
  %325 = add nsw i64 %324, -1
  %326 = sdiv i64 %325, 2
  %327 = getelementptr inbounds ptr, ptr %319, i64 %326
  %328 = load ptr, ptr %253, align 8
  %329 = load ptr, ptr %327, align 8
  %330 = call double @t2_sort_cmp_ab(ptr noundef %328, ptr noundef %329) #12
  %331 = fcmp ult double %330, 9.200000e+18
  %332 = fcmp ole double %330, -9.200000e+18
  %333 = fptosi double %330 to i64
  %334 = select i1 %332, i64 -1, i64 %333
  %335 = select i1 %331, i64 %334, i64 1
  %336 = icmp sgt i64 %335, -1
  %337 = icmp ne i64 %335, 0
  %338 = zext i1 %337 to i32
  %339 = icmp sgt i32 %338, %250
  %340 = and i1 %336, %339
  %341 = getelementptr inbounds ptr, ptr %327, i64 1
  %342 = select i1 %340, ptr %320, ptr %327
  %343 = select i1 %340, ptr %341, ptr %319
  %344 = icmp ult ptr %343, %342
  br i1 %344, label %318, label %345

345:                                              ; preds = %318, %313
  %346 = phi ptr [ %314, %313 ], [ %342, %318 ]
  %347 = icmp eq ptr %253, %240
  br i1 %347, label %348, label %357

348:                                              ; preds = %345, %348
  %349 = phi ptr [ %351, %348 ], [ %239, %345 ]
  %350 = phi ptr [ %353, %348 ], [ %238, %345 ]
  %351 = getelementptr inbounds ptr, ptr %349, i64 1
  %352 = load ptr, ptr %349, align 8
  %353 = getelementptr inbounds ptr, ptr %350, i64 1
  store ptr %352, ptr %350, align 8
  %354 = icmp ult ptr %351, %346
  br i1 %354, label %348, label %355

355:                                              ; preds = %348
  %356 = getelementptr inbounds ptr, ptr %240, i64 1
  br label %366

357:                                              ; preds = %345, %357
  %358 = phi ptr [ %360, %357 ], [ %240, %345 ]
  %359 = phi ptr [ %362, %357 ], [ %238, %345 ]
  %360 = getelementptr inbounds ptr, ptr %358, i64 1
  %361 = load ptr, ptr %358, align 8
  %362 = getelementptr inbounds ptr, ptr %359, i64 1
  store ptr %361, ptr %359, align 8
  %363 = icmp ult ptr %360, %346
  br i1 %363, label %357, label %364

364:                                              ; preds = %357
  %365 = getelementptr inbounds ptr, ptr %239, i64 1
  br label %366

366:                                              ; preds = %364, %355
  %367 = phi ptr [ %239, %364 ], [ %240, %355 ]
  %368 = phi ptr [ %362, %364 ], [ %353, %355 ]
  %369 = phi ptr [ %360, %364 ], [ %356, %355 ]
  %370 = phi ptr [ %365, %364 ], [ %351, %355 ]
  %371 = phi ptr [ %359, %364 ], [ %350, %355 ]
  %372 = load ptr, ptr %367, align 8
  store ptr %372, ptr %368, align 8
  %373 = getelementptr inbounds ptr, ptr %371, i64 2
  %374 = icmp ult ptr %369, %229
  %375 = icmp ult ptr %370, %233
  %376 = select i1 %374, i1 %375, i1 false
  br i1 %376, label %237, label %377

377:                                              ; preds = %366, %217
  %378 = phi ptr [ %223, %217 ], [ %369, %366 ]
  %379 = phi ptr [ %229, %217 ], [ %370, %366 ]
  %380 = phi ptr [ %224, %217 ], [ %373, %366 ]
  %381 = phi i1 [ %235, %217 ], [ %375, %366 ]
  %382 = icmp eq ptr %378, %229
  br i1 %382, label %383, label %391

383:                                              ; preds = %377
  br i1 %381, label %384, label %398

384:                                              ; preds = %383, %384
  %385 = phi ptr [ %387, %384 ], [ %379, %383 ]
  %386 = phi ptr [ %389, %384 ], [ %380, %383 ]
  %387 = getelementptr inbounds ptr, ptr %385, i64 1
  %388 = load ptr, ptr %385, align 8
  %389 = getelementptr inbounds ptr, ptr %386, i64 1
  store ptr %388, ptr %386, align 8
  %390 = icmp ult ptr %387, %233
  br i1 %390, label %384, label %398

391:                                              ; preds = %377, %391
  %392 = phi ptr [ %394, %391 ], [ %378, %377 ]
  %393 = phi ptr [ %396, %391 ], [ %380, %377 ]
  %394 = getelementptr inbounds ptr, ptr %392, i64 1
  %395 = load ptr, ptr %392, align 8
  %396 = getelementptr inbounds ptr, ptr %393, i64 1
  store ptr %395, ptr %393, align 8
  %397 = icmp ult ptr %394, %229
  br i1 %397, label %391, label %398

398:                                              ; preds = %391, %384, %383
  %399 = phi ptr [ %380, %383 ], [ %389, %384 ], [ %396, %391 ]
  %400 = ptrtoint ptr %399 to i64
  %401 = sub i64 %400, %227
  %402 = getelementptr inbounds i8, ptr %220, i64 %401
  store ptr %402, ptr %223, align 8
  %403 = add nsw i32 %218, -1
  %404 = icmp eq i32 %403, 0
  br i1 %404, label %407, label %405

405:                                              ; preds = %398
  %406 = getelementptr inbounds %struct.off_runs, ptr %219, i64 -1
  br label %407

407:                                              ; preds = %405, %398
  %408 = phi ptr [ %406, %405 ], [ %219, %398 ]
  %409 = phi i32 [ 0, %405 ], [ 20, %398 ]
  %410 = phi ptr [ %221, %405 ], [ %220, %398 ]
  %411 = phi ptr [ %220, %405 ], [ %221, %398 ]
  br i1 %404, label %416, label %412

412:                                              ; preds = %407
  %413 = getelementptr inbounds %struct.off_runs, ptr %408, i64 0, i32 1
  %414 = load i64, ptr %413, align 8
  %415 = icmp eq i64 %414, 0
  br i1 %415, label %217, label %416

416:                                              ; preds = %412, %407
  %417 = phi i32 [ %403, %412 ], [ 0, %407 ]
  %418 = phi i32 [ 0, %412 ], [ %409, %407 ]
  %419 = phi i64 [ %414, %412 ], [ 0, %407 ]
  %420 = ashr exact i64 %232, 3
  %421 = icmp eq i32 %418, 0
  br i1 %421, label %422, label %491

422:                                              ; preds = %416, %201
  %423 = phi i64 [ %420, %416 ], [ %202, %201 ]
  %424 = phi i32 [ %417, %416 ], [ %203, %201 ]
  %425 = phi ptr [ %408, %416 ], [ %204, %201 ]
  %426 = phi i64 [ %419, %416 ], [ %206, %201 ]
  %427 = getelementptr inbounds %struct.off_runs, ptr %425, i64 0, i32 1
  store i64 0, ptr %427, align 8
  %428 = icmp sgt i64 %426, 2
  br i1 %428, label %429, label %439

429:                                              ; preds = %422, %429
  %430 = phi i64 [ %437, %429 ], [ %426, %422 ]
  %431 = phi ptr [ %434, %429 ], [ %425, %422 ]
  %432 = phi i32 [ %433, %429 ], [ %424, %422 ]
  %433 = add nsw i32 %432, 1
  %434 = getelementptr inbounds %struct.off_runs, ptr %431, i64 1
  store i64 %423, ptr %434, align 8
  %435 = lshr i64 %430, 1
  %436 = getelementptr inbounds %struct.off_runs, ptr %431, i64 1, i32 1
  store i64 %435, ptr %436, align 8
  %437 = sub nsw i64 %430, %435
  %438 = icmp sgt i64 %437, 2
  br i1 %438, label %429, label %439

439:                                              ; preds = %429, %422
  %440 = phi i32 [ %424, %422 ], [ %433, %429 ]
  %441 = phi ptr [ %425, %422 ], [ %434, %429 ]
  %442 = phi i64 [ %426, %422 ], [ %437, %429 ]
  %443 = and i32 %440, 1
  %444 = icmp eq i64 %442, 1
  br i1 %444, label %445, label %466

445:                                              ; preds = %439
  %446 = icmp eq i32 %443, 0
  br i1 %446, label %463, label %447

447:                                              ; preds = %445
  %448 = getelementptr ptr, ptr %9, i64 %423
  %449 = getelementptr inbounds ptr, ptr %34, i64 %423
  %450 = load ptr, ptr %449, align 8
  %451 = ptrtoint ptr %450 to i64
  %452 = add i64 %199, %451
  %453 = shl nsw i64 %423, 3
  %454 = add i64 %453, %200
  %455 = call i64 @llvm.umax.i64(i64 %452, i64 %454)
  %456 = sub i64 %198, %453
  %457 = add i64 %456, %455
  %458 = and i64 %457, -8
  %459 = add i64 %458, 8
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %449, ptr align 8 %448, i64 %459, i1 false)
  %460 = sub i64 %451, %197
  %461 = ashr exact i64 %460, 3
  %462 = getelementptr inbounds i8, ptr %9, i64 %460
  store ptr %462, ptr %448, align 8
  br label %491

463:                                              ; preds = %445
  %464 = icmp eq i32 %440, 0
  %465 = select i1 %464, i32 20, i32 0
  br label %491

466:                                              ; preds = %439
  %467 = add nsw i32 %440, 1
  %468 = getelementptr inbounds %struct.off_runs, ptr %441, i64 1
  store i64 %423, ptr %468, align 8
  %469 = getelementptr inbounds %struct.off_runs, ptr %441, i64 1, i32 1
  store i64 0, ptr %469, align 8
  %470 = icmp eq i32 %443, 0
  br i1 %470, label %471, label %491

471:                                              ; preds = %466
  %472 = getelementptr ptr, ptr %9, i64 %423
  %473 = getelementptr inbounds ptr, ptr %34, i64 %423
  %474 = load ptr, ptr %473, align 8
  %475 = load ptr, ptr %474, align 8
  %476 = ptrtoint ptr %475 to i64
  %477 = add i64 %199, %476
  %478 = shl nsw i64 %423, 3
  %479 = add i64 %478, %200
  %480 = call i64 @llvm.umax.i64(i64 %477, i64 %479)
  %481 = sub i64 %198, %478
  %482 = add i64 %481, %480
  %483 = and i64 %482, -8
  %484 = add i64 %483, 8
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %473, ptr align 8 %472, i64 %484, i1 false)
  %485 = sub i64 %476, %197
  %486 = ptrtoint ptr %474 to i64
  %487 = sub i64 %486, %197
  %488 = ashr exact i64 %487, 3
  %489 = getelementptr inbounds i8, ptr %9, i64 %487
  %490 = getelementptr inbounds i8, ptr %9, i64 %485
  store ptr %489, ptr %472, align 8
  store ptr %490, ptr %489, align 8
  br label %491

491:                                              ; preds = %471, %466, %463, %447, %416
  %492 = phi i64 [ %420, %416 ], [ %461, %447 ], [ %423, %466 ], [ %488, %471 ], [ %423, %463 ]
  %493 = phi i32 [ %417, %416 ], [ %440, %447 ], [ %467, %466 ], [ %467, %471 ], [ %440, %463 ]
  %494 = phi ptr [ %408, %416 ], [ %441, %447 ], [ %468, %466 ], [ %468, %471 ], [ %441, %463 ]
  %495 = phi i32 [ %418, %416 ], [ 0, %447 ], [ 0, %466 ], [ 0, %471 ], [ %465, %463 ]
  switch i32 %495, label %499 [
    i32 0, label %201
    i32 20, label %496
  ]

496:                                              ; preds = %491
  %497 = icmp eq ptr %34, %3
  br i1 %497, label %499, label %498

498:                                              ; preds = %496
  call void @free(ptr noundef %34) #12
  br label %499

499:                                              ; preds = %491, %25, %496, %498
  call void @llvm.lifetime.end.p0(i64 960, ptr nonnull %5) #12
  call void @llvm.lifetime.end.p0(i64 24, ptr nonnull %4) #12
  call void @llvm.lifetime.end.p0(i64 1600, ptr nonnull %3) #12
  %500 = icmp sgt i64 %1, 0
  br i1 %500, label %501, label %508

501:                                              ; preds = %499, %501
  %502 = phi i64 [ %506, %501 ], [ 0, %499 ]
  %503 = getelementptr inbounds %struct.Slot, ptr %0, i64 %502
  %504 = getelementptr inbounds ptr, ptr %9, i64 %502
  %505 = load ptr, ptr %504, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %503, ptr noundef nonnull align 8 dereferenceable(16) %505, i64 16, i1 false)
  %506 = add nuw nsw i64 %502, 1
  %507 = icmp eq i64 %506, %1
  br i1 %507, label %508, label %501

508:                                              ; preds = %501, %499, %16
  %509 = phi i32 [ 1, %16 ], [ 0, %499 ], [ 0, %501 ]
  store ptr %12, ptr @msort_jb, align 8
  call void @free(ptr noundef %9) #12
  call void @free(ptr noundef %11) #12
  call void @llvm.lifetime.end.p0(i64 200, ptr nonnull %6) #12
  ret i32 %509
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #3

; Function Attrs: mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite)

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #5

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #3

; Function Attrs: nounwind returns_twice
declare i32 @_setjmp(ptr noundef) local_unnamed_addr #6

; Function Attrs: mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite)
declare void @free(ptr allocptr nocapture noundef) local_unnamed_addr #7


; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umax.i64(i64, i64) #9

attributes #0 = { noreturn nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { noreturn nounwind "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #2 = { nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #3 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #4 = { mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite) "alloc-family"="malloc" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #5 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #6 = { nounwind returns_twice "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #7 = { mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite) "alloc-family"="malloc" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #8 = { "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #9 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #10 = { noreturn nounwind }
attributes #11 = { nounwind allocsize(0) }
attributes #12 = { nounwind }
attributes #13 = { nounwind returns_twice }


; t2_ghash(g) / t2_garray(g): the file's hash or array a global holds, made
; the first time any function reaches it.
define internal %Slot @t2_ghash(%Slot* %g) {
entry:
  %v = load %Slot, %Slot* %g
  %t = extractvalue %Slot %v, 0
  %has = icmp eq i8 %t, 5
  br i1 %has, label %done, label %make
make:
  %h = call %Slot @t2_hnew()
  store %Slot %h, %Slot* %g
  ret %Slot %h
done:
  ret %Slot %v
}
define internal %Array* @t2_garray(%Slot* %g) {
entry:
  %v = load %Slot, %Slot* %g
  %t = extractvalue %Slot %v, 0
  %has = icmp eq i8 %t, 6
  br i1 %has, label %done, label %make
make:
  %a = call %Array* @t2_new_array()
  %i = ptrtoint %Array* %a to i64
  %s = call %Slot @t2_slot(i8 6, i64 %i)
  store %Slot %s, %Slot* %g
  ret %Array* %a
done:
  %p = extractvalue %Slot %v, 1
  %r = inttoptr i64 %p to %Array*
  ret %Array* %r
}
; t2_arev(a) -> a new list of a's elements, last first.
define internal %Array* @t2_arev(%Array* %a) {
entry:
  %r = call %Array* @t2_new_array()
  %n = call i64 @t2_alen(%Array* %a)
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %im)
  call void @t2_apush(%Array* %r, %Slot %v)
  br label %loop
done:
  ret %Array* %r
}
; WHOLE ASSIGN IN PLACE (`@a = LIST`, `%h = LIST` on the container a tie or a
; reference names): the list copied first -- it may read the aggregate --
; then, for a tied one, perl's calls; for any other, cleared and refilled.
@lit_tm_extend = private unnamed_addr constant [7 x i8] c"EXTEND\00"
define internal void @t2_aassign(%Array* %a, %Array* %l) {
entry:
  %c = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %c, %Array* %l)
  %n = call i64 @t2_alen(%Array* %c)
  %m = call %Meta* @t2_meta(%Array* %a)
  %d = icmp eq %Meta* %m, @t2_meta_default
  br i1 %d, label %plain, label %tied
plain:
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 0, i64* %lp
  call void @t2_aappend(%Array* %a, %Array* %c)
  ret void
tied:
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ca = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %ca, %Slot %o)
  %cm = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_clear, i64 0, i64 0), i64 5)
  %cr = call %Slot @t2_tie_call(%Array* %ca, %Str %cm)
  %xa = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %xa, %Slot %o)
  %ns = call %Slot @t2_box_i64(i64 %n)
  call void @t2_apush(%Array* %xa, %Slot %ns)
  %xm = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_extend, i64 0, i64 0), i64 6)
  %xr = call %Slot @t2_tie_call(%Array* %xa, %Str %xm)
  br label %loop
loop:
  %i = phi i64 [ 0, %tied ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %c, i64 %i)
  call void @t2_aset(%Array* %a, i64 %i, %Slot %v, i8* null, i64 0)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret void
}
define internal void @t2_hassign(%Slot %h, %Array* %l) {
entry:
  %c = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %c, %Array* %l)
  %a = call %Array* @t2_harr(%Slot %h)
  %m = call %Meta* @t2_meta(%Array* %a)
  %d = icmp eq %Meta* %m, @t2_meta_default
  br i1 %d, label %plain, label %tied
plain:
  ; (element 0 is the hash's class: kept)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 1, i64* %lp
  call void @t2_hfroma(%Slot %h, %Array* %c)
  ret void
tied:
  ; (a tie's hfroma is CLEAR, then STORE each pair)
  call void @t2_hfroma(%Slot %h, %Array* %c)
  ret void
}
; t2_mresolve(invocant, method, " at FILE line N.\n", start, mode) -> the method's code,
; looked up from (mode 0) the invocant's class, (1) start, a qualified name's
; package, or (2) start's @ISA, a SUPER:: call's; where perl dies (no class,
; no method), a die naming that class, and t2_nomethod's code.
define internal i8* @t2_mresolve(%Slot %inv, %Str %m, %Str %at, %Str %start, i8 %mode) {
entry:
  store %Str %at, %Str* @t2_call_at
  %t = extractvalue %Slot %inv, 0
  switch i8 %t, label %named [ i8 0, label %undef i8 5, label %ref i8 6, label %ref i8 7, label %unbl i8 8, label %ref i8 9, label %ref ]
undef:
  %u0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_cm, i64 0, i64 0), i64 19)
  %u1 = call %Str @t2_concat(%Str %u0, %Str %m)
  %u2 = call %Str @t2_str(i8* getelementptr ([24 x i8], [24 x i8]* @lit_undefv, i64 0, i64 0), i64 23)
  %u3 = call %Str @t2_concat(%Str %u1, %Str %u2)
  br label %die
ref:
  %cl = call %Slot @t2_class_of(%Slot %inv)
  %ct = extractvalue %Slot %cl, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %unbl
obj:
  %cn = call %Str @t2_slot_str(%Slot %cl)
  br label %look
unbl:
  %b0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_cm, i64 0, i64 0), i64 19)
  %b1 = call %Str @t2_concat(%Str %b0, %Str %m)
  %b2 = call %Str @t2_str(i8* getelementptr ([25 x i8], [25 x i8]* @lit_unbl, i64 0, i64 0), i64 24)
  %b3 = call %Str @t2_concat(%Str %b1, %Str %b2)
  br label %die
named:
  %nn = call %Str @t2_slot_str(%Slot %inv)
  %nl = extractvalue %Str %nn, 1
  %empty = icmp eq i64 %nl, 0
  br i1 %empty, label %nopkg, label %look
nopkg:
  %p0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_cm, i64 0, i64 0), i64 19)
  %p1 = call %Str @t2_concat(%Str %p0, %Str %m)
  %p2 = call %Str @t2_str(i8* getelementptr ([40 x i8], [40 x i8]* @lit_nopkg, i64 0, i64 0), i64 39)
  %p3 = call %Str @t2_concat(%Str %p1, %Str %p2)
  br label %die
look:
  %own = phi %Str [ %cn, %obj ], [ %nn, %named ]
  %fromown = icmp eq i8 %mode, 0
  %c = select i1 %fromown, %Str %own, %Str %start
  %super = icmp eq i8 %mode, 2
  %r = call i8* @t2_mfind_u(%Str %c, %Str %m, i1 %super)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ok, label %miss
ok:
  ret i8* %r
miss:
  %l0 = call %Str @t2_str(i8* getelementptr ([29 x i8], [29 x i8]* @lit_lom, i64 0, i64 0), i64 28)
  %l1 = call %Str @t2_concat(%Str %l0, %Str %m)
  %l2 = call %Str @t2_str(i8* getelementptr ([16 x i8], [16 x i8]* @lit_via, i64 0, i64 0), i64 15)
  %l3 = call %Str @t2_concat(%Str %l1, %Str %l2)
  %l4 = call %Str @t2_concat(%Str %l3, %Str %c)
  %tb = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %tb, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %quote, label %forgot
quote:
  %k0 = call %Str @t2_str(i8* getelementptr ([2 x i8], [2 x i8]* @lit_q, i64 0, i64 0), i64 1)
  %k1 = call %Str @t2_concat(%Str %l4, %Str %k0)
  br label %die
forgot:
  %f0 = call %Str @t2_str(i8* getelementptr ([32 x i8], [32 x i8]* @lit_forgot, i64 0, i64 0), i64 31)
  %f1 = call %Str @t2_concat(%Str %l4, %Str %f0)
  %f2 = call %Str @t2_concat(%Str %f1, %Str %c)
  %f3 = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_qp, i64 0, i64 0), i64 3)
  %f4 = call %Str @t2_concat(%Str %f2, %Str %f3)
  br label %die
die:
  %msg = phi %Str [ %u3, %undef ], [ %b3, %unbl ], [ %p3, %nopkg ], [ %k1, %quote ], [ %f4, %forgot ]
  %full = call %Str @t2_concat(%Str %msg, %Str %at)
  call void @t2_die_unwind(%Str %full)
  ret i8* bitcast (%Slot (%Array*)* @t2_nomethod to i8*)
}
; t2_nomethod(@_) -> undef: called where no method was found, a die already set.
define internal %Slot @t2_nomethod(%Array* %args) {
entry:
  ret %Slot zeroinitializer
}
define internal %Slot @t2_hget_d(%Slot %h, %Str %k) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %undef, label %get
get:
  %j = add i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %j)
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
define internal i1 @t2_hexists_d(%Slot %h, %Str %k) {
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %e = icmp sge i64 %i, 0
  ret i1 %e
}
; t2_hdelete(h, k) -> k's value (undef if none), its pair taken out.
define internal %Slot @t2_hdelete_d(%Slot %h, %Str %k) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %none, label %take
none:
  ret %Slot zeroinitializer
take:
  %j = add i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %j)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  %n = load i64, i64* %lp
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %d = phi i64 [ %i, %take ], [ %d2, %move ]
  %src = add i64 %d, 2
  %more = icmp slt i64 %src, %n
  br i1 %more, label %move, label %done
move:
  %sp = getelementptr %Slot, %Slot* %els, i64 %src
  %sv = load %Slot, %Slot* %sp
  %dp = getelementptr %Slot, %Slot* %els, i64 %d
  store %Slot %sv, %Slot* %dp
  %d2 = add i64 %d, 1
  br label %loop
done:
  %n2 = sub i64 %n, 2
  store i64 %n2, i64* %lp
  ret %Slot %v
}
define internal void @t2_hfroma_d(%Slot %h, %Array* %l) {
entry:
  %n = call i64 @t2_alen(%Array* %l)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %ks = call %Slot @t2_aget(%Array* %l, i64 %i)
  %k = call %Str @t2_slot_str(%Slot %ks)
  %j = add i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %l, i64 %j)
  call void @t2_hset(%Slot %h, %Str %k, %Slot %v)
  %i2 = add i64 %i, 2
  br label %loop
done:
  ret void
}
define internal i64 @t2_hcount_d(%Slot %h) {
  %a = call %Array* @t2_harr(%Slot %h)
  %n = call i64 @t2_alen(%Array* %a)
  %p = sub i64 %n, 1
  %c = sdiv i64 %p, 2
  ret i64 %c
}
; t2_hpick(h, from) -> every other element of the hash's pairs from index
; from: 1 its keys, 2 its values.
define internal %Array* @t2_hpick(%Slot %h, i64 %from) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %n = call i64 @t2_alen(%Array* %a)
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ %from, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i2 = add i64 %i, 2
  br label %loop
done:
  ret %Array* %r
}
define internal %Array* @t2_hpairs_d(%Slot %h) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %n = call i64 @t2_alen(%Array* %a)
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 1, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
define internal %Array* @t2_hkeys_d(%Slot %h) {
  %r = call %Array* @t2_hpick(%Slot %h, i64 1)
  ret %Array* %r
}
define internal %Array* @t2_hvalues_d(%Slot %h) {
  %r = call %Array* @t2_hpick(%Slot %h, i64 2)
  ret %Array* %r
}
define internal void @t2_hset_d(%Slot %h, %Str %k, %Slot %v) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %add, label %put
add:
  %ks = call %Slot @t2_box_str(%Str %k)
  call void @t2_apush(%Array* %a, %Slot %ks)
  call void @t2_apush(%Array* %a, %Slot %v)
  ret void
put:
  %j = add i64 %i, 1
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  store %Slot %v, %Slot* %p
  ret void
}
LL

1;
