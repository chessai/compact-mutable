{-# LANGUAGE DataKinds #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE TypeFamilies #-}

{-# OPTIONS_GHC -O2 #-}

import Data.Primitive.Compact
import GHC.Compact
import GHC.Prim
import Data.Word
import Data.Primitive.Array
import Data.Primitive.PrimArray
import Data.Primitive.ByteArray
import Data.Primitive.PrimRef
import Data.Primitive
import Data.Functor.Identity
import Data.Int
import Control.Monad

main :: IO ()
main = do
  putStrLn "Running compact-mutable tests"
  putStrLn "Trying normal compact functions as sanity check"
  _ <- newArray 13 (44 :: Int) >>= unsafeFreezeArray >>= compact
  _ <- newArray 11 (42 :: Int) >>= (\m -> freezeArray m 0 5) >>= compact
  nums <- newPrimArray 15 :: IO (MutablePrimArray RealWorld Int64)
  writePrimArray nums 0 58
  nums2 <- fmap getCompact $ compact nums
  nums2Alias <- fmap getCompact $ compact nums2
  writePrimArray nums2Alias 0 57
  originalVal <- readPrimArray nums 0
  copyVal <- readPrimArray nums2 0
  aliasVal <- readPrimArray nums2Alias 0
  when (originalVal /= 58) $ fail "original value wrong"
  when (copyVal /= 58) $ fail "copy value wrong"
  when (aliasVal /= 57) $ fail "alias value wrong"
  withToken $ \token -> do
    -- putStrLn "creating array"
    -- _ <- newCompactArray token 5
    -- putStrLn "creating mutable array"
    -- _ <- newCompactArray token 5
    -- putStrLn "creating array of arrays"
    -- c1 <- newCompactArray token 12
    -- c2 <- newCompactArray token 5
    -- writeCompactArray c1 0 (Yes c2)
    -- unsafeInsertCompactArray 4 2 (Yes c2) c1
    -- writeCompactArray c1 1 No
    -- x <- readCompactArray c1 1
    -- case x of
    --   No -> return ()
    --   Yes _ -> fail "did not get expected value"
    -- copyCompactMutableArray c1 0 c1 4 3
    -- c3 <- newCompactArray token 16
    -- _ <- compactAddGeneral token (Identity c1)
    -- _ <- compactAddGeneral token (Identity c3)
    -- putStrLn "creating PrimRef"
    p1 <- Ref <$> newPrimRef (12 :: Word16)
    p2 <- compactAddGeneral token p1
    -- p9 <- compactAddGeneral token (Thing (12 :: Word32))
    -- -- !p3 <- compactAddGeneral token p2
    -- _ <- newCompactArray token 3
    putStrLn "attempting large loop"
    arr <- newCompactArray token 10000000
    let go !n = if n < 10000000
          then do
            !p3 <- compactAddGeneral token (Thing n)
            writeCompactArray arr n p3
            go (n + 1)
          else return ()
    go 0
    -- printCompactArrayAddrs arr
    let goRead !n = if n < 10000000
          then do
            Thing val <- readCompactArray arr n
            -- val <- readPrimRef r
            if val == n
              then return ()
              else fail "found value not equal to n"
            goRead (n + 1)
          else return ()
    goRead 0
    putStrLn "finished large loop"
    putStrLn "aliasing behavior"
    a1 <- newCompactArray token 10
    writeCompactArray a1 0 (Thing (79 :: Int))
    a2 <- compactAddGeneral token a1
    a3 <- compactAddGeneral token a2
    writeCompactArray a3 0 (Thing (74 :: Int))
    Thing n <- readCompactArray a1 0
    when (n /= 74) $ fail "wrong value of n"
    putStrLn "finished aliasing behavior"
    putStrLn "testing contractible array"
    k1 <- newContractedArray token 2
    k5 <- newContractedArray token 3
    writeContractedArray k1 0 (Foo 55 k1)
    writeContractedArray k1 1 (Foo 12 k5)
    writeContractedArray k5 0 (Foo 33 k5)
    writeContractedArray k5 1 (Foo 42 k1)
    Foo n k2 <- readContractedArray k1 0
    Foo m k3 <- readContractedArray k2 0
    Foo _ k6 <- readContractedArray k5 0
    Foo _ k7 <- readContractedArray k5 1
    Foo _ _ <- readContractedArray k6 0
    Foo _ _ <- readContractedArray k7 1
    unsafeInsertContractedArray 2 1 (Foo 124 k1) k5
    Foo _ k8 <- readContractedArray k5 2
    Foo _ _ <- readContractedArray k8 1
    Foo _ k9 <- readContractedArray k5 1
    Foo _ _ <- readContractedArray k9 1
    if n == 55
      then return ()
      else fail "n should be 55"
    if m == 55
      then return ()
      else fail "m should be 55"
    putStrLn "successful contractible array"
    return ()

-- Note: making types like this to put in a compact array is not
-- typically safe. Do not do it unless you understand how the compact
-- heap works.
data Thing a (c :: Heap) = Thing !a
data MaybeArray (c :: Heap) = No | Yes (CompactMutableArray RealWorld MaybeArray c)
data Ref (c :: Heap) = Ref !(PrimRef RealWorld Word16)

data Foo s c = Foo
  {-# UNPACK #-} !Int
  {-# UNPACK #-} !(ContractedMutableArray s (Foo s) c)

instance Contractible (Foo s) where
  unsafeSizeOfContractedElement _ = sizeOf (undefined :: Int) * 2
  unsafeWriteContractedArray (ContractedMutableArray marr) ix (Foo n (ContractedMutableArray (MutableByteArray nodes))) = do
    let machIx = ix * 2
    writeByteArray marr (machIx + 0) n
    writeByteArray marr (machIx + 1) (unsafeUnliftedToAddr nodes)
  unsafeReadContractedArray (ContractedMutableArray marr) ix = do
    let machIx = ix * 2
    a <- readByteArray marr (machIx + 0)
    f <- readByteArray marr (machIx + 1)
    return (Foo a (ContractedMutableArray (MutableByteArray (unsafeUnliftedFromAddr f))))


