{-# LANGUAGE RecordWildCards, QuasiQuotes #-}

module Toy.Language.Compiler where

import Data.List
import Data.String.Interpolate

import Toy.Language.Syntax.Decl
import Toy.Language.Syntax.Types

compileFunDecl :: FunDecl -> String
compileFunDecl FunDecl { .. } = [i|#{funName} : #{compileTy funTy}|]

compileTy :: Ty -> String
compileTy (TyBase RefinedBaseTy { .. })
  | baseTyRefinement == trueRefinement = compileBaseTy baseType
  | otherwise = [i| (ν : #{compileBaseTy baseType} ** #{compileRefinement baseTyRefinement}) |]
compileTy (TyArrow ArrowTy { .. }) = [i|#{lhs} -> #{compileTy codTy}|]
  where
    lhs | Just name <- piVarName = [i|(#{getName name} : #{compileTy domTy})|]
        | otherwise = compileTy domTy

compileRefinement :: Refinement -> String
compileRefinement refinement =
  case conjuncts refinement of
       [] -> "()"
       [conj] -> compileAR conj
       conjs -> "(" <> intercalate ", " (compileAR <$> conjs) <> ")"

compileAR :: AtomicRefinement -> String
compileAR (AR op arg) = [i|ν #{opStr} #{argStr}|]
  where
    opStr = case op of
                 ROpLe -> "<"
                 ROpLeq -> "<="
                 ROpEq -> "=="
                 ROpNEq -> "/="
                 ROpGe -> ">"
                 ROpGeq -> ">="
    argStr = case arg of
                  RArgZero -> "0"
                  RArgVar var -> getName var
                  RArgVarLen var -> "length " <> getName var

compileBaseTy :: BaseTy -> String
compileBaseTy TBool = "Bool"
compileBaseTy TInt = "Int"