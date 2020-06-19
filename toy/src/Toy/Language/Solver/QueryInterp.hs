{-# LANGUAGE ConstraintKinds, FlexibleContexts #-}
{-# LANGUAGE RecordWildCards, QuasiQuotes, LambdaCase #-}

module Toy.Language.Solver.QueryInterp
( convertIntrinsics
) where

import qualified Data.HashMap.Strict as HM
import Control.Conditional
import Control.Monad.State.Strict
import Data.Foldable
import Data.String.Interpolate
import Z3.Monad

import Toy.Language.Solver.Types
import Toy.Language.Syntax

newtype Z3Var = Z3Var { getZ3Var :: AST }

newtype ConvertState = ConvertState { variables :: HM.HashMap VarName Z3Var }

type MonadConvert m = (MonadZ3 m, MonadState ConvertState m)

convertIntrinsics :: MonadConvert m => RefAnnTerm -> m AST
convertIntrinsics term = do
  mapM_ (\RefAnn { .. } -> createVar tyAnn $ subjectVar intrinsic) refinements
  mapM (convertRefinement . intrinsic) refinements >>= mkAnd
  where
    refinements = toList term

convertRefinement :: MonadConvert m => Refinement -> m AST
convertRefinement Refinement { .. } = mapM (convertTerm . getARTerm) conjuncts >>= mkAnd
  where
    convertTerm = \case
      TName _ varName -> getZ3Var <$> getVar varName
      TInteger _ n -> mkIntNum n
      TBinOp _ t1 op t2 -> join $ convertBinOp op <$> convertTerm t1 <*> convertTerm t2
      TApp _ fun arg -> error "fun app at refinement level unsupported yet" -- TODO
      TIfThenElse { .. } -> do
        tthenCond' <- convertTerm tcond
        tthen' <- convertTerm tthen

        telseCond' <- mkNot tthenCond'
        telse' <- convertTerm telse

        thenBranch <- mkImplies tthenCond' tthen'
        elseBranch <- mkImplies telseCond' telse'

        mkAnd [thenBranch, elseBranch]
    convertBinOp = \case
      BinOpPlus -> \a b -> mkAdd [a, b]
      BinOpMinus -> \a b -> mkAdd [a, b]
      BinOpLt -> mkLt
      BinOpLeq -> mkLe
      BinOpEq -> mkEq
      BinOpNEq -> \a b -> mkEq a b >>= mkNot
      BinOpGt -> mkGt
      BinOpGeq -> mkGe

createVar :: MonadConvert m => Ty -> VarName -> m Z3Var
createVar ty varName = do
  ifM (gets $ HM.member varName . variables)
    (error [i|#{getName varName} has already been instantiated|])
    (pure ())
  z3var <- Z3Var <$> mkFreshTypedVar ty (getName varName)
  modify' $ \cs -> cs { variables = HM.insert varName z3var $ variables cs }
  pure z3var
  where
    mkFreshTypedVar (TyBase rbty) = case baseType rbty of
                                         TInt -> mkFreshIntVar
                                         TBool -> mkFreshBoolVar
                                         TIntList -> error "TODO TIntList unsupported" -- TODO
    mkFreshTypedVar TyArrow {} = \name -> mkStringSymbol name >>= mkUninterpretedSort >>= mkFreshConst name

getVar :: MonadConvert m => VarName -> m Z3Var
getVar varName = gets $ (HM.! varName) . variables
