{-# LANGUAGE ForeignFunctionInterface #-}

-- |
-- Module      : Data.CryptoHash.MD4
-- License     : BSD-style
-- Maintainer  : Vincent Hanquez <vincent@snarc.org>
-- Stability   : experimental
-- Portability : unknown
--
-- A module containing MD4 bindings
--
module Data.CryptoHash.MD4 (
	-- * Incremental hashing Functions
	init,      -- :: Ctx
	update,    -- :: Ctx -> ByteString -> Ctx
	finalize,  -- :: Ctx -> ByteString

	-- * Single Pass hashing
	hash,      -- :: ByteString -> ByteString
	hashlazy   -- :: ByteString -> ByteString
	) where

import Prelude hiding (init)
import Foreign
import Foreign.C.String
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import Data.ByteString (ByteString)
import Data.ByteString.Unsafe (unsafeUseAsCStringLen)

data Ctx = Ctx ![Word32]

digestSize :: Int
sizeCtx :: Int

digestSize = 16
sizeCtx = 88

sizeCtxW :: Int
sizeCtxW = sizeCtx `div` 4

instance Storable Ctx where
	sizeOf _    = sizeCtx
	alignment _ = 16
	poke ptr (Ctx l) = do
		let bptr = castPtr ptr :: Ptr Word32
		mapM_ (\(i, v) -> poke (bptr `plusPtr` (i*4)) v) $ zip [0..(sizeCtxW-1)] l

	peek ptr = do
		let bptr = castPtr ptr :: Ptr Word32
		l <- mapM (\i -> peek $ bptr `plusPtr` (i*4)) [0..(sizeCtxW-1)]
		return (Ctx l)

foreign import ccall unsafe "md4.h md4_init"
	c_md4_init :: Ptr Ctx -> IO ()

foreign import ccall unsafe "md4.h md4_update"
	c_md4_update :: Ptr Ctx -> CString -> Word32 -> IO ()

foreign import ccall unsafe "md4.h md4_finalize"
	c_md4_finalize :: Ptr Ctx -> CString -> IO ()

allocInternal :: (Ptr Ctx -> IO a) -> IO a
allocInternal = alloca

allocInternalFrom :: Ctx -> (Ptr Ctx -> IO a) -> IO a
allocInternalFrom ctx f = allocInternal $ \ptr -> (poke ptr ctx >> f ptr)

updateInternalIO :: Ptr Ctx -> ByteString -> IO ()
updateInternalIO ptr d =
	unsafeUseAsCStringLen d (\(cs, len) -> c_md4_update ptr cs (fromIntegral len))

finalizeInternalIO :: Ptr Ctx -> IO ByteString
finalizeInternalIO ptr =
	allocaBytes digestSize (\cs -> c_md4_finalize ptr cs >> B.packCStringLen (cs, digestSize))

-- | init a context
init :: Ctx
init = unsafePerformIO $ allocInternal $ \ptr -> do (c_md4_init ptr >> peek ptr)

-- | update a context with a bytestring
update :: Ctx -> ByteString -> Ctx
update ctx d = unsafePerformIO $ allocInternalFrom ctx $ \ptr -> do updateInternalIO ptr d >> peek ptr

-- | finalize the context into a digest bytestring
finalize :: Ctx -> ByteString
finalize ctx = unsafePerformIO $ allocInternalFrom ctx $ \ptr -> do finalizeInternalIO ptr

-- | hash a strict bytestring into a digest bytestring
hash :: ByteString -> ByteString
hash d = unsafePerformIO $ allocInternal $ \ptr -> do
	c_md4_init ptr >> updateInternalIO ptr d >> finalizeInternalIO ptr

-- | hash a lazy bytestring into a digest bytestring
hashlazy :: L.ByteString -> ByteString
hashlazy l = unsafePerformIO $ allocInternal $ \ptr -> do
	c_md4_init ptr >> mapM_ (updateInternalIO ptr) (L.toChunks l) >> finalizeInternalIO ptr