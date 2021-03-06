{-# LANGUAGE QuasiQuotes #-}

module T30TermsCompilerSpec(spec) where

import Data.String.Interpolate
import Test.Hspec

import Idris.IdeModeClient
import Toy.Language.BasicTC
import Toy.Language.Compiler
import Toy.Language.Solver.QueryGen
import Toy.Language.Solver.QueryInterp
import Toy.Language.Solver.Types

import TestUtils

checkIdris :: String -> IdrisHandle -> Expectation
checkIdris program ih = do
  (ctx, (sig, def)) <- testParseFunWithCtx program
  let typedDef = annotateFunDef ctx sig def
  let qdef = genQueriesFunDef sig typedDef
  (res, solvedFunDef) <- solveDef sig qdef
  res `shouldBe` Correct
  runIdrisClient ih $ withFile $ \file -> do
    writePrelude file
    mapM_ (write file . compileFunSig) ctx
    write file $ compileFunSig sig
    write file $ compileFunDef sig solvedFunDef
    testIdrisFile file

spec :: Spec
spec = testWithIdris $ do
  describe "Terms with unrefined types" $ do
    it "translates constants" $ checkIdris
      [i|
         someNum : Int
         someNum = 42
        |]
    it "translates variables" $ checkIdris
      [i|
         id' : Int -> Int
         id' x = x
        |]
    it "translates binary arithmetic operations" $ checkIdris
      [i|
         add : Int -> Int -> Int
         add a b = a + b
        |]
    it "translates relational operations" $ checkIdris
      [i|
         gt : Int -> Int -> Bool
         gt a b = a > b
        |]
    it "translates applying function to a constant" $ checkIdris
      [i|
         f : (Int -> Int) -> Int
         f g = g 0
        |]
    it "translates applying function to a function" $ checkIdris
      [i|
         f : ((Int -> Int) -> Int) -> (Int -> Int) -> Int
         f g h = g h
        |]
    it "translates applying more functions to functions" $ checkIdris
      [i|
         f : ((Int -> Int) -> Int -> Int) -> (Int -> Int) -> Int
         f g h = (g h) (g h 0)
        |]
    it "translates if-then-else" $ checkIdris
      [i|
         max : Int -> Int -> Int
         max a b = if a > b then a else b
        |]
    describe "if-then-else fun" $ do
      xit "translates if-then-else applied to a variable" $ checkIdris -- TODO idris 2 dependent if
        [i|
           sel : Bool -> (Int -> Int) -> (Int -> Int) -> Int -> Int
           sel b f g x = (if b then f else g) x
          |]
      it "translates a function applied to if-then-else" $ checkIdris
        [i|
           sel : Bool -> (Int -> Int) -> Int -> Int -> Int
           sel b f x y = f (if b then x else y)
          |]
      it "translates funapps inside if-then-else branches" $ checkIdris
        [i|
           sel : Bool -> (Int -> Int) -> (Int -> Int) -> Int -> Int -> Int
           sel b f g x y = if b then f x else g y
          |]
  describe "Basic context" $
    it "uses definitions" $ checkIdris
      [i|
         f : Int -> Int

         g : Int
         g = f 0
        |]
  describe "Terms with refined types" $ do
    it "translates constants" $ checkIdris
      [i|
         someNum : { v : Int | v = 42 }
         someNum = 42
        |]
    it "translates sort-of-identity" $ checkIdris
      [i|
         stupidId : { v : Int | v >= 0 } -> { v : Int | v >= 0 }
         stupidId x = x
        |]
    it "translates weakening sort-of-identity" $ checkIdris
      [i|
         stupidId : { v : Int | v > 0 } -> { v : Int | v >= 0 }
         stupidId x = x
        |]
    describe "Path sensitivity" $ do
      it "compiles ReLu" $ checkIdris
        [i|
           relu : Int -> { v : Int | v >= 0 }
           relu x = if x > 0 then x else 0
          |]
      it "compiles stricter ReLu" $ checkIdris
        [i|
           relu : (x : Int) -> { v : Int | v >= 0 & v >= x }
           relu x = if x > 0 then x else 0
          |]
      it "compiles max" $ checkIdris
        [i|
           max : (x : Int) -> (y : Int) -> { v : Int | v >= x & v >= y }
           max x y = if x > y then x else y
          |]
      it "compiles 3-max" $ checkIdris
        [i|
           max : (x : Int) -> (y : Int) -> (z : Int) -> { v : Int | v >= x & v >= y & v >= z }
           max x y z = if x > y then if x > z then x else z else if y > z then y else z
          |]
    describe "Basic function application" $ do
      it "translates function application" $ checkIdris
        [i|
           f : { v : Int | v >= 0 } -> Int

           g : Int
           g = f 42
          |]
      it "weakens the result of function application (with a constant)" $ checkIdris
        [i|
           f : { v : Int | v >= 0 } -> { v : Int | v > 0 }

           g : { v : Int | v >= 0 }
           g = f 42
          |]
      it "weakens the result of function application (with an arg)" $ checkIdris
        [i|
           f : { v : Int | v >= 0 } -> { v : Int | v > 0 }

           g : { v : Int | v > 0 } -> { v : Int | v >= 0 }
           g x = f x
          |]
      it "compiles refined `add`" $ checkIdris
        [i|
           add : (x : { v : Int | v >= 0 }) -> (y : { v : Int | v >= 0 }) -> { v : Int | v >= x & v >= y }
           add x y = x + y
          |]
      it "compiles correct subtyping queries" $ checkIdris
        [i|
           g : { v : Int | v >= 0 } -> Int

           f : { v : Int | v > 0 } -> Int
           f x = g x
          |]
      it "compiles correct dependent subtyping queries" $ checkIdris
        [i|
           g : (x : Int) -> (x1 : { v : Int | v >= x }) -> (x2 : { v : Int | v >= x1 }) -> Int

           f : (x : Int) -> (x1 : { v : Int | v > x }) -> (x2 : { v : Int | v > x1 }) -> Int
           f x x1 x2 = g x x1 x2
          |]
      it "compiles correct dependent subtyping queries (substituting)" $ checkIdris
        [i|
           g : (z : Int) -> (z1 : { v : Int | v >= z }) -> (z2 : { v : Int | v >= z1 }) -> Int

           f : (x : Int) -> (x1 : { v : Int | v > x }) -> (x2 : { v : Int | v > x1 }) -> Int
           f x x1 x2 = g x x1 x2
          |]
      it "compiles correct dependent subtyping queries (substituting-2)" $ checkIdris
        [i|
           g : (z : Int) -> (z1 : { v : Int | v >= z }) -> (z2 : { v : Int | v >= z1 }) -> Int

           f : (x1 : { v : Int | v > 0 }) -> (x2 : { v : Int | v > x1 }) -> Int
           f x1 x2 = g 0 x1 x2
          |]
      it "compiles max(x, 0)" $ checkIdris
        [i|
           max : (x : Int) -> (y : Int) -> { v : Int | v >= x & v >= y }

           f : Int -> { v : Int | v >= 0 }
           f x = max x 0
          |]
      it "compiles max(x, 0) with max as arg" $ checkIdris
        [i|
           f : (max : (x : Int) -> (y : Int) -> { v : Int | v >= x & v >= y }) -> Int -> { v : Int | v >= 0 }
           f max x = max x 0
          |]
      it "compiles add(x, 0)" $ checkIdris
        [i|
           add : (x : { v : Int | v >= 0 }) -> (y : { v : Int | v >= 0 }) -> { v : Int | v >= x & v >= y }

           f : (x : { v : Int | v >= 0 }) -> { v : Int | v >= 0 & v >= x }
           f x = add x 0
          |]
      it "compiles passing functions to functions" $ checkIdris
        [i|
           f : (x : { v : Int | v >= 0 }) -> (y : { v : Int | v >= 0 }) -> { v : Int | v >= 0 }

           g : ((x : { v : Int | v >= 0 }) -> (y : { v : Int | v >= 0 }) -> { v : Int | v >= 0 }) -> Int

           h : Int
           h = g f
          |]
      it "compiles more complicated function application" $ checkIdris
        [i|
           f : { v : Int | v >= 0 } -> { v : Int | v > 0 }
           h : { v : Int | v >= 0 } -> { v : Int | v > 0 }
           g : { v : Int | v >= 0 } -> { v : Int | v >= 0 } -> { v : Int | v > 0 }

           fun : { v : Int | v > 0 } -> { v : Int | v > 0 } -> { v : Int | v >= 0 }
           fun x y = g (f x) (h y)
          |]
      it "compiles correct functional argument refinements" $ checkIdris
        [i|
           f : (x : { v : Int | v >= 0 }) -> (y : { v : Int | v >= 0 }) -> { v : Int | v > 0 }

           g : ((x : { v : Int | v > 0 }) -> (y : { v : Int | v > 0 }) -> { v : Int | v >= 0 }) -> Int

           h : Int
           h = g f
          |]
      it "compiles correct results of function application" $ checkIdris
        [i|
           f : (x : { v : Int | v >= 0 }) -> (y : { v : Int | v >= 0 }) -> { v : Int | v > 0 }

           g : ((x : { v : Int | v > 0 }) -> (y : { v : Int | v > 0 }) -> { v : Int | v >= 0 }) -> { v : Int | v >= 0 }

           h : { v : Int | v >= 0 }
           h = g f
          |]
