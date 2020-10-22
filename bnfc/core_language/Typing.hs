-- Typing of expressions

module Typing where

-- import qualified Prelude as C (Eq, Ord, Show, Read)
import AbsSyntax
import Data.List

----------------------------------------------------------------------
-- Environment
----------------------------------------------------------------------

-- Typing is done in an environment, composed of
-- the global decls of a module and
-- local variable declarations
data LocalVarDecls = LVD [(VarName, Tp)]
  deriving (Eq, Ord, Show, Read)
data Environment t = Env (Module t) LocalVarDecls
  deriving (Eq, Ord, Show, Read)

module_of_env :: Environment t -> Module t
module_of_env (Env m _) = m

locals_of_env :: Environment t -> [(VarName,Tp)]
locals_of_env (Env _ (LVD ls)) = ls


----------------------------------------------------------------------
-- Class manipulation
----------------------------------------------------------------------

class_def_assoc :: [ClassDecl t] -> [(ClassName, ClassDef t)]
class_def_assoc = map (\(ClsDecl cn cdf) -> (cn, cdf))

field_assoc ::  [ClassDecl t] -> [(ClassName, [FieldDecl])]
field_assoc = map (\(ClsDecl cn cdf) -> (cn, fields_of_class_def cdf))


-- For a class name 'cn', returns the list of the names of the superclasses of 'cn'
-- Here, 'cdf_assoc' is an association of class names and class defs as contained in a module.
-- 'visited' is the list of class names already visited on the way up the class hierarchy
super_classes :: [(ClassName, ClassDef (Maybe ClassName))] -> [ClassName] -> ClassName -> [ClassName]
super_classes cdf_assoc visited cn =
  case lookup cn cdf_assoc of
    -- the following should not happen if defined_superclass is true in a module
    Nothing -> error "in super_classes: cn not in cdf_assoc (internal error)"
    -- reached the top of the hierarchy
    Just (ClsDef Nothing _) -> reverse (cn : visited)
    -- class has super-class with name scn
    Just (ClsDef (Just scn) _) -> 
      if elem scn visited
      then error ("cyclic superclass hierarchy for class " ++ (case cn of (ClsNm n) -> n))
      else super_classes cdf_assoc (cn : visited) scn 

-- For each of a list of class declarations, returns its list of superclass names
super_classes_decls :: [ClassDecl (Maybe ClassName)] -> [[ClassName]]
super_classes_decls cds =
  let cdf_assoc = class_def_assoc cds
  in map (super_classes cdf_assoc []) (map fst cdf_assoc)


-- in a class declaration, replace the reference to the immediate super-class by the list of all super-classes
elaborate_supers_in_class_decls :: [ClassDecl (Maybe ClassName)] -> [ClassDecl [ClassName]]
elaborate_supers_in_class_decls cds =
  let cdf_assoc = class_def_assoc cds
  in map (\(ClsDecl cn (ClsDef mcn fds)) -> (ClsDecl cn (ClsDef (tail (super_classes cdf_assoc [] cn)) fds))) cds


local_fields :: [(ClassName, [FieldDecl])] -> ClassName -> [FieldDecl]
local_fields fd_assoc cn =
  case lookup cn fd_assoc of
    Nothing -> []
    Just fds -> fds

-- in a class declaration, replace the list of local fields of the class by the list of all fields (local and inherited)
elaborate_fields_in_class_decls :: [ClassDecl [ClassName]] -> [ClassDecl [ClassName]]
elaborate_fields_in_class_decls cds =
  let fd_assoc = field_assoc cds
  in map (\(ClsDecl cn (ClsDef scs locfds)) ->
            (ClsDecl cn (ClsDef scs (locfds ++ (concatMap (local_fields fd_assoc) scs))))) cds
  

-- $> super_classes_decls customCs

-- $> elaborate_fields_in_class_decls (elaborate_supers_in_class_decls customCs)

-- Cyclic superclass hierarchy:
-- $> super_classes_decls [ClsDecl (ClsNm "Foo") (ClsDef (Just (ClsNm "Bar")) []), ClsDecl (ClsNm "Bar") (ClsDef (Just (ClsNm "Foo")) [])]


-- the class decl does not reference an undefined superclass
defined_superclass :: [ClassName] -> ClassDecl (Maybe ClassName) -> Bool
defined_superclass cns cdc =
  case cdc of
    (ClsDecl cn (ClsDef Nothing _)) -> True
    (ClsDecl cn (ClsDef (Just scn) _)) ->
      if elem scn cns
      then True
      else error ("undefined superclass for class " ++ (case cn of (ClsNm n) -> n))


hasDuplicates :: (Ord a) => [a] -> Bool
hasDuplicates xs = length (nub xs) /= length xs

wellformed_class_decls_in_module :: Module (Maybe ClassName) -> Bool
wellformed_class_decls_in_module md =
  case md of
    (Mdl cds rls) ->
      let class_names = map name_of_class_decl cds
      in all (defined_superclass class_names) cds && not (hasDuplicates (map name_of_class_decl cds))

-- TODO: still check that field decls only reference declared classes
well_formed_field_decls :: ClassDecl t -> Bool
well_formed_field_decls (ClsDecl cn cdf) = not (hasDuplicates (fields_of_class_def cdf))

-- TODO: a bit of a hack. Error detection and treatment to be improved
-- - no ref to undefined superclass
-- - no cyclic graph hierarchy (implemented in super_classes above)
-- - no duplicate field declarations (local and inherited)
elaborate_module :: Module (Maybe ClassName) -> Module [ClassName]
elaborate_module md =
  if wellformed_class_decls_in_module md
  then
    case md of
      Mdl cds rls ->
        let ecdcs = (elaborate_fields_in_class_decls (elaborate_supers_in_class_decls cds))
        in
          if all well_formed_field_decls ecdcs
          then Mdl ecdcs rls
          else error "Problem in field declarations: duplicate field declarations"
  else error "Problem in class declarations"

-- $> elaborate_module (Mdl customCs [])


strict_superclasses_of :: Module [ClassName] -> ClassName -> [ClassName]
strict_superclasses_of md cn = case lookup cn (class_def_assoc (class_decls_of_module md)) of
  Nothing -> error ("in strict_superclasses_of: undefined class " ++ (case cn of (ClsNm n) -> n))
  Just (ClsDef supcls _) -> supcls
  
is_strict_subclass_of :: Module [ClassName] -> ClassName -> ClassName -> Bool
is_strict_subclass_of md subcl supercl = elem subcl (strict_superclasses_of md subcl)

is_subclass_of :: Module [ClassName] -> ClassName -> ClassName -> Bool
is_subclass_of md subcl supercl = subcl == supercl || is_strict_subclass_of md subcl supercl

----------------------------------------------------------------------
-- Typing functions
----------------------------------------------------------------------

lookup_class_def_in_env :: Environment t -> ClassName -> [ClassDef t]
lookup_class_def_in_env env cn =
  map def_of_class_decl (filter (\cd -> name_of_class_decl cd == cn) (class_decls_of_module (module_of_env env)))

tp_constval :: Environment t -> Val -> Tp
tp_constval env x = case x of
  BoolV _ -> BoolT
  IntV _ -> IntT
  -- for record values to be well-typed, the fields have to correspond exactly (incl. order of fields) to the class fields.
  -- TODO: maybe relax some of these conditions.
  RecordV cn fnvals -> 
    let tfnvals = map (\(fn, v) -> FldDecl fn (tp_constval env v)) fnvals
    in case lookup_class_def_in_env env cn of
       [] -> error ("class name " ++ (case cn of (ClsNm n) -> n) ++ " not defined")
       [cd] ->
         if fields_of_class_def cd == tfnvals
         then ClassT cn
         else error ("record fields do not correspond to fields of class " ++ (case cn of (ClsNm n) -> n))
       _ -> error "internal error: duplicate class definition"

tp_var :: Environment t -> VarName -> Tp
tp_var env v =
  case lookup v (locals_of_env env) of
    Nothing -> ErrT
    Just t -> t  

tp_of_expr :: Exp t -> t
tp_of_expr x = case x of
  ValE t _      -> t
  VarE t _        -> t
  UnaOpE t _ _    -> t
  BinOpE t _ _ _  -> t
  IfThenElseE t _ _ _ -> t
  AppE t _ _  -> t
  FunE t _ _ _  -> t
  CastE t _ _     -> t
  ListE t _ _     -> t


tp_uarith :: Tp -> UArithOp -> Tp
tp_uarith t ua = if t == IntT then IntT else ErrT

tp_ubool :: Tp -> UBoolOp -> Tp
tp_ubool t ub = if t == BoolT then BoolT else ErrT

tp_unaop :: Tp -> UnaOp -> Tp
tp_unaop t uop = case uop of
  UArith ua  -> tp_uarith t ua
  UBool ub   -> tp_ubool t ub


tp_barith :: Tp -> Tp -> BArithOp -> Tp
tp_barith t1 t2 ba = if (t1 == t2) && t1 == IntT then IntT else ErrT

tp_bcompar :: Tp -> Tp -> BComparOp -> Tp
tp_bcompar t1 t2 bc = if (t1 == t2) then BoolT else ErrT

tp_bbool :: Tp -> Tp -> BBoolOp -> Tp
tp_bbool t1 t2 bc = if (t1 == t2) && t1 == BoolT then BoolT else ErrT

tp_binop :: Tp -> Tp -> BinOp -> Tp
tp_binop t1 t2 bop = case bop of
  BArith ba  -> tp_barith t1 t2 ba
  BCompar bc -> tp_bcompar t1 t2 bc
  BBool bb   -> tp_bbool t1 t2 bb


-- the first type can be cast to the second type
-- TODO: still to be defined
cast_compatible :: Tp -> Tp -> Bool
cast_compatible te ctp = True


push_vardecl_env :: VarName -> Tp -> Environment t -> Environment t
push_vardecl_env vn t (Env md (LVD vds)) = Env md (LVD ((vn, t):vds))


-- TODO: FldAccE, ListE
tp_expr :: Environment t -> Exp () -> Exp Tp
tp_expr env x = case x of
  ValE () c -> ValE (tp_constval env c) c
  VarE () v -> VarE (tp_var env v) v
  UnaOpE () uop e -> 
    let te = (tp_expr env e)
        t   = tp_unaop (tp_of_expr te) uop
    in  UnaOpE t uop te
  BinOpE () bop e1 e2 ->
    let te1 = (tp_expr env e1)
        te2 = (tp_expr env e2)
        t   = tp_binop (tp_of_expr te1) (tp_of_expr te2) bop
    in  BinOpE t bop te1 te2
  IfThenElseE () c e1 e2 -> 
    let tc = (tp_expr env c)
        te1 = (tp_expr env e1)
        te2 = (tp_expr env e2)
    in
      if tp_of_expr tc == BoolT && (tp_of_expr te1) == (tp_of_expr te2)
      then IfThenElseE (tp_of_expr te1) tc te1 te2
      else  IfThenElseE ErrT tc te1 te2
  AppE () fe ae -> 
    let tfe = (tp_expr env fe)
        tae = (tp_expr env ae)
        tf = (tp_of_expr tfe)
        ta = (tp_of_expr tae)
    in case tf of
      FunT tpar tbody ->
        if tpar == ta
        then AppE tbody tfe tae
        else AppE ErrT tfe tae
      _ -> AppE ErrT tfe tae
  FunE () v tparam e -> 
    let te = (tp_expr (push_vardecl_env v tparam env) e)
        t   = (tp_of_expr te)
    in FunE (FunT tparam t) v tparam te
  -- ClosE: no explicit typing because not externally visible
  CastE () ctp e ->        
    let te = (tp_expr env e)
    in if cast_compatible (tp_of_expr te) ctp
       then CastE ctp ctp te
       else CastE ErrT ctp te



----------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------


-- $> tp_expr (Env preambleMdl (LVD [])) (AppE () (FunE () (VarNm "x") IntT (VarE () (VarNm "x"))) (ValE () (IntV 3)))

-- $> tp_expr (Env (elaborate_module preambleMdl) (LVD [])) (ValE () (RecordV (ClsNm "SGD") [(FldNm "val", IntV 50)]))

-- $> tp_expr (Env preambleMdl (LVD [])) (BinOpE () (BCompar BClte) (BinOpE () (BArith BAadd) (ValE () (IntV 50)) (BinOpE () (BArith BAmul) (BinOpE () (BArith BAadd) (ValE () (IntV 90)) (ValE () (IntV 4))) (VarE () (VarNm "foo")))) (BinOpE () (BArith BAmul) (ValE () (IntV 2)) (ValE () (IntV 5))))

-- $> tp_expr (Env preambleMdl (LVD [(VarNm "foo", IntT)])) (BinOpE () (BCompar BClte) (BinOpE () (BArith BAadd) (ValE () (IntV 50)) (BinOpE () (BArith BAmul) (BinOpE () (BArith BAadd) (ValE () (IntV 90)) (ValE () (IntV 4))) (VarE () (VarNm "foo")))) (BinOpE () (BArith BAmul) (ValE () (IntV 2)) (ValE () (IntV 5))))



-- $> tp_expr (Env preambleMdl (LVD [])) (UnaOpE () (UBool UBneg) (BinOpE () (BCompar BClte) (ValE () (IntV 2)) (BinOpE () (BArith BAmul) (ValE () (IntV 2)) (ValE () (IntV 5)))))


-- $> tp_expr (Env preambleMdl (LVD [])) (ValE () (IntV 5))



----------------------------------------------------------------------
-- Typing Timed Automata
----------------------------------------------------------------------

clock_of_constraint :: ClConstr -> Clock
clock_of_constraint (ClCn c _ _) = c

-- TODO: move into preamble file
list_subset :: Eq a => [a] -> [a] -> Bool
list_subset xs ys = all (\x -> elem x ys) xs

-- TODO: move into preamble file
distinct :: Eq a => [a] -> Bool
distinct [] = True
distinct (x : xs) =  if elem x xs then False else distinct xs


well_formed_action :: [ClassName] -> Action -> Bool
well_formed_action ta_act_clss Internal = True
well_formed_action ta_act_clss (Act cn _) = elem cn ta_act_clss

well_formed_transition :: Module [ClassName] -> [Loc] -> [ClassName] -> [Clock] -> Transition -> Bool
well_formed_transition md ta_locs ta_act_clss ta_clks (Trans l1 ccs act clks l2) = 
  elem l1 ta_locs && elem l2 ta_locs &&
  well_formed_action ta_act_clss act &&
  list_subset (map clock_of_constraint ccs) ta_clks  &&
  list_subset clks ta_clks

well_formed_ta :: Environment [ClassName] -> TA () -> TA Tp
well_formed_ta env (TmdAut nm ta_locs ta_act_clss ta_clks trans init_locs invs lbls) =
  if
    all (well_formed_transition (module_of_env env) ta_locs ta_act_clss ta_clks) trans &&
    all (\act_cls -> is_subclass_of (module_of_env env) act_cls (ClsNm "Event")) ta_act_clss &&
    all (\(l, ccs) -> elem l ta_locs && list_subset (map clock_of_constraint ccs) ta_clks) invs
  then
    let lbls_locs = map fst lbls
        tes = map (tp_expr env) (map snd lbls)
    in
      if all (\l -> elem l ta_locs) lbls_locs && all (\te -> tp_of_expr te == BoolT) tes
      then (TmdAut nm ta_locs ta_act_clss ta_clks trans init_locs invs (zip lbls_locs tes))
      else error "ill-formed timed automaton (labels)"
  else error "ill-formed timed automaton (transitions)"
      
well_formed_ta_sys :: Environment [ClassName] -> TASys () -> TASys Tp
well_formed_ta_sys env (TmdAutSys tas) =
  if distinct (map name_of_ta tas)
  then TmdAutSys (map (well_formed_ta env) tas)
  else error "duplicate TA names"
  

